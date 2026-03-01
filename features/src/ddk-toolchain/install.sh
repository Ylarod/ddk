#!/usr/bin/env bash
set -euo pipefail

log() { echo "[ddk-toolchain] $*"; }

_ANDROID_VER="${ANDROIDVER:-${ANDROID_VER:-${androidVer:-android12-5.10}}}"
_SET_DEFAULT="${SETDEFAULT:-${SET_DEFAULT:-${setDefault:-true}}}"

DDK_ROOT=/opt/ddk
URL_BASE="https://cnb.cool/Ylarod/ddk-prebuilts/-/lfs"
RAW_BASE="https://cnb.cool/Ylarod/ddk-prebuilts/-/git/raw/main"
MAPPING_URL="https://cnb.cool/Ylarod/ddk/-/git/raw/main/mapping.json"

require_tools() {
  command -v tar >/dev/null || { echo "需要 tar"; exit 1; }
  command -v zstd >/dev/null || echo "[warn] 未检测到 zstd，尝试 tar 直接解压（可能失败）" >&2
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

fetch() {
  local url="$1"; local out="$2"
  if have_cmd curl; then
    curl -fL "$url" -o "$out"
  elif have_cmd wget; then
    wget -q "$url" -O "$out"
  else
    echo "需要 curl 或 wget 用于下载：$url"; exit 1
  fi
}

fetch_text() {
  local url="$1"
  if have_cmd curl; then
    curl -fsSL "$url" || true
  elif have_cmd wget; then
    wget -qO- "$url" || true
  else
    return 0
  fi
}

auto_oid_from_pointer() {
  local path_rel="$1"
  local url="$RAW_BASE/$path_rel"
  local content
  content=$(fetch_text "$url")
  if [ -n "$content" ]; then
    printf "%s" "$content" | awk -F: '/^oid sha256:/ {gsub(/[[:space:]]/, "", $2); print $2; exit}'
  fi
}

sha256_of() {
  local f="$1"
  if have_cmd sha256sum; then
    sha256sum "$f" | awk '{print $1}'
  elif have_cmd shasum; then
    shasum -a 256 "$f" | awk '{print $1}'
  elif have_cmd python3; then
    python3 - "$f" <<'PY'
import hashlib,sys
h=hashlib.sha256()
with open(sys.argv[1],'rb') as fp:
    for chunk in iter(lambda: fp.read(1<<20), b''):
        h.update(chunk)
print(h.hexdigest())
PY
  else
    echo "" # 无校验
  fi
}

extract_zst() {
  local src="$1"; local dest="$2"
  mkdir -p "$dest"
  if have_cmd zstd; then
    zstd -d -c "$src" | tar -x -C "$dest"
  else
    tar -I zstd -xf "$src" -C "$dest" || {
      echo "解压失败：缺少 zstd"; exit 1;
    }
  fi
}

# 通用下载并解压函数
download_and_extract() {
  local name="$1"        # 显示名称
  local lfs_subdir="$2"  # LFS 子目录
  local filename="$3"    # 文件名
  local dest_dir="$4"    # 解压目标目录

  log "尝试从 raw 指针文件自动解析 $name sha256"
  local sha256
  sha256=$(auto_oid_from_pointer "$lfs_subdir/$filename" || true)
  if [ -z "$sha256" ]; then
    log "$name 指针解析失败，跳过下载"
    return 1
  fi
  local url="$URL_BASE/$sha256?name=$filename"
  log "解析到 sha256: $sha256"
  local tmp="/tmp/$filename"
  log "下载: $url"
  fetch "$url" "$tmp"
  local got
  got=$(sha256_of "$tmp" || true)
  if [ -n "$got" ] && [ "$got" != "$sha256" ]; then
    echo "sha256 校验失败：期望 $sha256 实际 $got" >&2
    exit 1
  fi
  extract_zst "$tmp" "$dest_dir"
  rm -f "$tmp"
}

# 从远程 mapping.json 解析工具链版本
resolve_versions() {
  log "从远程 mapping.json 解析 $_ANDROID_VER 的工具链版本"
  local mapping
  mapping=$(fetch_text "$MAPPING_URL")
  if [ -z "$mapping" ]; then
    echo "无法获取 mapping.json" >&2
    exit 1
  fi

  if ! have_cmd jq; then
    log "未检测到 jq，尝试使用 python3 解析"
    if ! have_cmd python3; then
      echo "需要 jq 或 python3 来解析 mapping.json" >&2
      exit 1
    fi
    eval "$(python3 - "$_ANDROID_VER" <<'PY'
import json,sys
ver = sys.argv[1]
data = json.load(sys.stdin)
for entry in data.get("matrix", []):
    if entry.get("android") == ver:
        print(f'_CLANG_VER="{entry.get("clang", "")}"')
        rust = entry.get("rust") or ""
        print(f'_RUST_VER="{rust}"')
        sys.exit(0)
print(f'echo "未找到 {ver} 的矩阵条目" >&2; exit 1', file=sys.stderr)
sys.exit(1)
PY
    <<< "$mapping")"
  else
    _CLANG_VER=$(printf '%s' "$mapping" | jq -r --arg ver "$_ANDROID_VER" '.matrix[] | select(.android == $ver) | .clang')
    _RUST_VER=$(printf '%s' "$mapping" | jq -r --arg ver "$_ANDROID_VER" '.matrix[] | select(.android == $ver) | .rust // ""')
  fi

  if [ -z "$_CLANG_VER" ]; then
    echo "未找到 $_ANDROID_VER 对应的 Clang 版本" >&2
    exit 1
  fi
  log "解析结果: Clang=$_CLANG_VER Rust=${_RUST_VER:-（无）}"
}

write_profile() {
  [ "$_SET_DEFAULT" = "true" ] || return 0
  local clang_dest="$DDK_ROOT/clang/$_CLANG_VER"
  [ -x "$clang_dest/bin/clang" ] || return 0
  local bashrc="/etc/bash.bashrc"
  touch "$bashrc"
  # 移除旧的标记块（兼容旧 ddk-clang 标记），保持幂等更新
  sed '/^## ddk-clang begin$/, /^## ddk-clang end$/d' "$bashrc" >"${bashrc}.tmp" || true
  mv "${bashrc}.tmp" "$bashrc"
  sed '/^## ddk-toolchain begin$/, /^## ddk-toolchain end$/d' "$bashrc" >"${bashrc}.tmp" || true
  mv "${bashrc}.tmp" "$bashrc"
  {
    echo "## ddk-toolchain begin"
    echo "export DDK_ROOT=\"$DDK_ROOT\""
    echo "export CLANG_VER=\"$_CLANG_VER\""
    echo "export CLANG_PATH=\"$clang_dest/bin\""
    echo "export PATH=\"$clang_dest/bin\":\$PATH"
    if [ -n "$_RUST_VER" ] && [ -d "$DDK_ROOT/rust/$_RUST_VER/bin" ]; then
      echo "export RUST_VER=\"$_RUST_VER\""
      echo "export RUST_PATH=\"$DDK_ROOT/rust/$_RUST_VER/bin\""
      echo "export PATH=\"$DDK_ROOT/rust/$_RUST_VER/bin\":\$PATH"
    fi
    echo "## ddk-toolchain end"
  } >>"$bashrc"
}

main() {
  require_tools
  resolve_versions

  local clang_dest_dir="$DDK_ROOT/clang"
  local clang_dest_ver="$clang_dest_dir/$_CLANG_VER"

  # --- Clang ---
  log "准备 Clang: $_CLANG_VER"
  mkdir -p "$clang_dest_dir"
  if [ -x "$clang_dest_ver/bin/clang" ]; then
    log "Clang 已存在，跳过：$clang_dest_ver"
  else
    download_and_extract "Clang" "clang" "$_CLANG_VER.tar.zst" "$clang_dest_dir" || true
    log "Clang 已展开到：$clang_dest_ver"
  fi

  # --- Rust（可选）---
  if [ -n "$_RUST_VER" ]; then
    local rust_dest_dir="$DDK_ROOT/rust"
    local rust_dest_ver="$rust_dest_dir/$_RUST_VER"
    log "准备 Rust: $_RUST_VER"
    mkdir -p "$rust_dest_dir"
    if [ -d "$rust_dest_ver/bin" ]; then
      log "Rust 已存在，跳过：$rust_dest_ver"
    else
      download_and_extract "Rust" "rust" "$_RUST_VER.tar.zst" "$rust_dest_dir" || true
      log "Rust 已展开到：$rust_dest_ver"
    fi
  fi

  write_profile
  log "完成。CLANG_PATH=$clang_dest_ver/bin"
  [ -z "$_RUST_VER" ] || log "RUST_PATH=$DDK_ROOT/rust/$_RUST_VER/bin"
}

main "$@"

#!/usr/bin/env bash
set -euo pipefail

log() { echo "[ddk-clang] $*"; }

_CLANG_VER="${CLANGVER:-${CLANG_VER:-${clangVer:-clang-r416183b}}}"
_SET_DEFAULT="${SETDEFAULT:-${SET_DEFAULT:-${setDefault:-true}}}"

DDK_ROOT=/opt/ddk
DEST_DIR="$DDK_ROOT/clang"
DEST_VER_DIR="$DEST_DIR/$_CLANG_VER"
FILENAME="$_CLANG_VER.tar.zst"
URL_BASE="https://cnb.cool/Ylarod/ddk/-/lfs"
RAW_BASE="https://cnb.cool/Ylarod/ddk/-/git/raw/main"

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
  local path_rel="$1"   # 例如: clang/clang-r416183b.tar.zst
  local url="$RAW_BASE/$path_rel"
  local content
  content=$(fetch_text "$url")
  if [ -n "$content" ]; then
    # 从指针文件解析 sha256
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
    # 某些 tar 支持 -I zstd
    tar -I zstd -xf "$src" -C "$dest" || {
      echo "解压失败：缺少 zstd"; exit 1;
    }
  fi
}

write_profile() {
  [ "$_SET_DEFAULT" = "true" ] || return 0
  [ -x "$DEST_VER_DIR/bin/clang" ] || return 0
  local bashrc="/etc/bash.bashrc"
  # 确保文件存在
  touch "$bashrc"
  # 移除旧的标记块，保持幂等更新
  sed '/^## ddk-clang begin$/, /^## ddk-clang end$/d' "$bashrc" >"${bashrc}.tmp" || true
  mv "${bashrc}.tmp" "$bashrc"
  # 追加新的标记块
  cat >>"$bashrc" <<EOF
## ddk-clang begin
export DDK_ROOT="$DDK_ROOT"
export CLANG_VER="$_CLANG_VER"
export CLANG_PATH="$DEST_VER_DIR/bin"
export PATH="$DEST_VER_DIR/bin":$PATH
## ddk-clang end
EOF
}

main() {
  log "准备 Clang: $_CLANG_VER"
  require_tools
  mkdir -p "$DEST_DIR"

  if [ -x "$DEST_VER_DIR/bin/clang" ]; then
    log "已存在，跳过：$DEST_VER_DIR"
  else
    log "尝试从 raw 指针文件自动解析 sha256"
    _SHA256=$(auto_oid_from_pointer "clang/$FILENAME" || true)
    if [ -z "${_SHA256}" ]; then
      log "解析失败，跳过下载"
      write_profile
      return 0
    fi
    URL="$URL_BASE/$_SHA256?name=$FILENAME"
    log "解析到 sha256: $_SHA256"
    local tmp="/tmp/$FILENAME"
    log "下载: $URL"
    fetch "$URL" "$tmp"
    # 校验（如工具可用）
    local got
    got=$(sha256_of "$tmp" || true)
    if [ -n "$got" ] && [ "$got" != "${_SHA256}" ]; then
      echo "sha256 校验失败：期望 ${_SHA256} 实际 $got" >&2
      exit 1
    fi
    extract_zst "$tmp" "$DEST_DIR"
    rm -f "$tmp"
    log "已展开到：$DEST_VER_DIR"
  fi

  write_profile
  log "完成。CLANG_PATH=$DEST_VER_DIR/bin"
}

main "$@"

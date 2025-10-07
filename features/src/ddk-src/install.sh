#!/usr/bin/env bash
set -euo pipefail

log() { echo "[ddk-src] $*"; }

_ANDROID_VER="${ANDROIDVER:-${ANDROID_VER:-${androidVer:-android12-5.10}}}"
_WITH_KDIR="${WITHKDIR:-${WITH_KDIR:-${withKdir:-false}}}"
_SET_DEFAULT="${SETDEFAULT:-${SET_DEFAULT:-${setDefault:-true}}}"

DDK_ROOT=/opt/ddk
SRC_DEST_DIR="$DDK_ROOT/src"
SRC_DIR="$SRC_DEST_DIR/$_ANDROID_VER"
SRC_FILENAME="src.$_ANDROID_VER.tar.zst"
KDIR_DEST_DIR="$DDK_ROOT/kdir"
KDIR_DIR="$KDIR_DEST_DIR/$_ANDROID_VER"
KDIR_FILENAME="kdir.$_ANDROID_VER.tar.zst"
URL_BASE="https://cnb.cool/Ylarod/ddk/-/lfs"
RAW_BASE="https://cnb.cool/Ylarod/ddk/-/git/raw/main"

have_cmd() { command -v "$1" >/dev/null 2>&1; }

require_tools() {
  command -v tar >/dev/null || { echo "需要 tar"; exit 1; }
  command -v zstd >/dev/null || echo "[warn] 未检测到 zstd，尝试 tar 直接解压（可能失败）" >&2
}

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
    echo ""
  fi
}

extract_zst() {
  local src="$1"; local dest="$2"
  mkdir -p "$dest"
  if have_cmd zstd; then
    zstd -d -c "$src" | tar -x -C "$dest"
  else
    tar -I zstd -xf "$src" -C "$dest" || { echo "解压失败：缺少 zstd"; exit 1; }
  fi
}

auto_oid_from_pointer() {
  local path_rel="$1"   # e.g., src/src.android14-6.1.tar.zst 或 kdir/kdir.android14-6.1.tar.zst
  local url="$RAW_BASE/$path_rel"
  local content
  content=$(fetch_text "$url")
  if [ -n "$content" ]; then
    printf "%s" "$content" | awk -F: '/^oid sha256:/ {gsub(/[[:space:]]/, "", $2); print $2; exit}'
  fi
}

write_profile() {
  [ "$_SET_DEFAULT" = "true" ] || return 0
  [ -d "$SRC_DIR" ] || return 0
  local bashrc="/etc/bash.bashrc"
  local kdir_line=""
  if [ "$_WITH_KDIR" = "true" ] && [ -d "$KDIR_DIR" ]; then
    kdir_line="export KDIR=\"$KDIR_DIR\""
  fi
  # 确保文件存在
  touch "$bashrc"
  # 移除旧的标记块，保持幂等更新
  sed '/^## ddk-src begin$/, /^## ddk-src end$/d' "$bashrc" >"${bashrc}.tmp" || true
  mv "${bashrc}.tmp" "$bashrc"
  # 追加新的标记块
  cat >>"$bashrc" <<EOF
## ddk-src begin
export DDK_ROOT="$DDK_ROOT"
export ANDROID_VER="$_ANDROID_VER"
${kdir_line}
## ddk-src end
EOF
}

main() {
  log "准备 Kernel 源：$_ANDROID_VER"
  require_tools
  mkdir -p "$SRC_DEST_DIR"
  if [ -d "$SRC_DIR" ]; then
    log "已存在，跳过：$SRC_DIR"
  else
    log "尝试从 raw 指针文件自动解析 src sha256"
    _SHA256=$(auto_oid_from_pointer "src/$SRC_FILENAME" || true)
    if [ -z "${_SHA256}" ]; then
      log "解析失败，跳过下载"
      write_profile
      return 0
    fi
    SRC_URL="$URL_BASE/$_SHA256?name=$SRC_FILENAME"
    log "解析到 sha256: $_SHA256"
    local tmp="/tmp/$SRC_FILENAME"
    log "下载: $SRC_URL"
    fetch "$SRC_URL" "$tmp"
    local got
    got=$(sha256_of "$tmp" || true)
    if [ -n "$got" ] && [ "$got" != "${_SHA256}" ]; then
      echo "sha256 校验失败：期望 ${_SHA256} 实际 $got" >&2
      exit 1
    fi
    extract_zst "$tmp" "$SRC_DEST_DIR"
    rm -f "$tmp"
    log "已展开到：$SRC_DIR"
  fi
  if [ "$_WITH_KDIR" = "true" ]; then
    mkdir -p "$KDIR_DEST_DIR"
    if [ -d "$KDIR_DIR" ]; then
      log "kdir 已存在，跳过：$KDIR_DIR"
    else
      log "尝试从 raw 指针文件自动解析 kdir sha256"
      _KDIR_SHA256=$(auto_oid_from_pointer "kdir/$KDIR_FILENAME" || true)
      if [ -n "${_KDIR_SHA256}" ]; then
        KDIR_URL="$URL_BASE/$_KDIR_SHA256?name=$KDIR_FILENAME"
        log "解析到 sha256: $_KDIR_SHA256"
        local tmpk="/tmp/$KDIR_FILENAME"
        log "下载 kdir: $KDIR_URL"
        fetch "$KDIR_URL" "$tmpk"
        local gotk
        gotk=$(sha256_of "$tmpk" || true)
        if [ -n "$gotk" ] && [ "$gotk" != "${_KDIR_SHA256}" ]; then
          echo "kdir sha256 校验失败：期望 ${_KDIR_SHA256} 实际 $gotk" >&2
          exit 1
        fi
        extract_zst "$tmpk" "$KDIR_DEST_DIR"
        rm -f "$tmpk"
        log "kdir 已展开到：$KDIR_DIR"
      else
        log "解析失败，跳过 kdir 下载"
      fi
    fi
  fi
  write_profile
  log "完成。SRC=$SRC_DIR${_WITH_KDIR:+ KDIR=$KDIR_DIR}"
}

main "$@"

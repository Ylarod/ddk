#!/usr/bin/env bash

# If not running in /opt/ddk, bind-mount current directory to /opt/ddk and cd there
if [ "$PWD" != "/opt/ddk" ]; then
  if [ ! -d /opt/ddk ]; then
    sudo mkdir -p /opt/ddk
  fi
  if ! mountpoint -q /opt/ddk; then
    echo "[+] Bind-mounting $PWD -> /opt/ddk"
    sudo mount --bind "$PWD" /opt/ddk
  fi
  cd /opt/ddk || { echo "Failed to cd /opt/ddk"; exit 1; }
fi

source ./envsetup.sh

if [ -f setup.lock ]; then
    echo "[!] Already setup, skip"
    return
fi

MAP_FILE=${MAP_FILE:-./mapping.json}
if [ ! -f "$MAP_FILE" ]; then
  echo "[x] 未找到 mapping.json: $MAP_FILE"
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "[x] 需要 jq 解析 $MAP_FILE，请先安装 jq"
  echo "    例如: sudo apt-get install -y jq 或 brew install jq"
  exit 3
fi

echo "[+] Setup clang"
# 解析 clang 数组: { version, branch }
jq -r '.clang[] | [.branch, .version] | @tsv' "$MAP_FILE" | while IFS=$'\t' read -r branch version; do
  [ -n "$branch" ] && [ -n "$version" ] || continue
  setup_clang "$branch" "$version"
done

echo "[+] Setup kernel source"
# 解析 android 数组: { name, branch }
jq -r '.android[] | [.name, .branch] | @tsv' "$MAP_FILE" | while IFS=$'\t' read -r name branch; do
  [ -n "$name" ] || continue
  # setup_source 如果 branch 为空会回退为 name
  setup_source "$name" "$branch"
done

echo "[+] Build kernel"
# 解析 matrix 数组: { android, clang }
jq -r '.matrix[] | [.clang, .android] | @tsv' "$MAP_FILE" | while IFS=$'\t' read -r clang_ver android_ver; do
  [ -n "$clang_ver" ] && [ -n "$android_ver" ] || continue
  build_kernel "$clang_ver" "$android_ver"
done

touch setup.lock

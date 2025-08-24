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

rm -rf kdir/android-*

echo "[+] Build kernel"
build_kernel clang-r416183b android12-5.10
build_kernel clang-r450784e android13-5.10
build_kernel clang-r450784e android13-5.15
build_kernel clang-r487747c android14-5.15
build_kernel clang-r487747c android14-6.1
build_kernel clang-r510928 android15-6.6
build_kernel clang-r536225 android16-6.12

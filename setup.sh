#!/usr/bin/env bash

source ./envsetup.sh

if [ -f setup.lock ]; then
    echo "[!] Already setup, skip"
    return
fi

echo "[+] Setup clang"
setup_clang master-kernel-build-2021 clang-r416183b
setup_clang master-kernel-build-2022 clang-r450784e
setup_clang main-kernel-build-2023 clang-r487747c

echo "[+] Setup kernel source"
setup_source android12-5.10
setup_source android13-5.15
setup_source android14-6.1

echo "[+] Patch kernel"
set -x
for dir in src/*; do 
    pushd $dir
    sed -i '/check_exports(mod);/s/^/\/\//' scripts/mod/modpost.c
    popd
done
set +x

echo "[+] Build kernel"
build_kernel clang-r416183b android12-5.10
build_kernel clang-r450784e android13-5.15
build_kernel clang-r487747c android14-6.1

touch setup.lock

#!/usr/bin/env bash

function setup_clang()
{
    local branch=$1
    local version=$2
    if [ -d clang/$version ]; then
        echo "[!] $version already exists, skip"
        return
    fi
    local url_prefix=https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads
    local url=$url_prefix/$branch/$version.tar.gz
    echo "[+] Download from $url"
    wget $url
    mkdir -p clang/$version
    tar xzvf $version.tar.gz -C clang/$version
}

function setup_source()
{
    local branch=$1
    if [ -d src/$branch ]; then
        echo "[!] $branch already exists, skip"
        return
    fi
    echo "[+] Clone $branch"
    git clone https://android.googlesource.com/kernel/common -b $branch --depth 1 src/$branch
}

function build_kernel()
{
    local clang_version=$1
    local branch=$2
    if [ -d kdir/$branch ]; then
        echo "[!] $branch already exists, skip"
        return
    fi
    local cache_path=$PATH
    local out_path=$(realpath kdir/$branch)
    local clang_path=$(realpath clang/$clang_version/bin)
    echo "[+] Building $branch"
    # setup env
    set -x
    export PATH=$clang_path:$cache_path
    export CROSS_COMPILE=aarch64-linux-gnu-
    export ARCH=arm64
    export LLVM=1
    export LLVM_IAS=1
    cd src/$branch
    make O=$out_path gki_defconfig
    make O=$out_path -j$(nproc)
    set +x
    cd ../..
    # restore path
    export PATH=$cache_path
}
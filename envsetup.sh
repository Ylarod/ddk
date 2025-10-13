#!/usr/bin/env bash

function setup_clang()
{
    local branch=$1
    local version=$2
    if [ -d /opt/ddk/clang/$version ]; then
        echo "[!] $version already exists, skip"
        return
    fi
    local url_prefix=https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads
    local url=$url_prefix/$branch/$version.tar.gz
    echo "[+] Download from $url"
    wget $url
    mkdir -p /opt/ddk/clang/$version
    tar xzvf $version.tar.gz -C /opt/ddk/clang/$version
}

function setup_source()
{
    local name=$1
    local branch=$2
    if [ -z "$branch" ]; then
        branch="$name"
    fi
    if [ -d /opt/ddk/src/$name ]; then
        echo "[!] $name already exists, skip"
        return
    fi
    echo "[+] Clone $name (branch: $branch)"
    git clone https://android.googlesource.com/kernel/common -b $branch --depth 1 /opt/ddk/src/$name
    pushd /opt/ddk/src/$name
    sed -i '/check_exports(mod);/s/^/\/\//' scripts/mod/modpost.c
    popd
}

function build_kernel()
{
    local clang_version=$1
    local branch=$2
    if [ -d /opt/ddk/kdir/$branch ]; then
        echo "[!] $branch already exists, skip"
        return
    fi
    local cache_path=$PATH
    local out_path=$(realpath /opt/ddk/kdir/$branch)
    local clang_path=$(realpath /opt/ddk/clang/$clang_version/bin)
    echo "[+] Building $branch"
    # setup env
    set -x
    export PATH=$clang_path:$cache_path
    export CROSS_COMPILE=aarch64-linux-gnu-
    export ARCH=arm64
    export LLVM=1
    export LLVM_IAS=1
    pushd /opt/ddk/src/$branch
    make O=$out_path gki_defconfig
    if [ "${LTO}" = "none" ]; then
        scripts/config --file $out_path/.config \
        -d LTO_CLANG \
        -e LTO_NONE \
        -d LTO_CLANG_THIN \
        -d LTO_CLANG_FULL \
        -d THINLTO
    elif [ "${LTO}" = "thin" ]; then
        # This is best-effort; some kernels don't support LTO_THIN mode
        # THINLTO was the old name for LTO_THIN, and it was 'default y'
        scripts/config --file $out_path/.config \
        -e LTO_CLANG \
        -d LTO_NONE \
        -e LTO_CLANG_THIN \
        -d LTO_CLANG_FULL \
        -e THINLTO
    elif [ "${LTO}" = "full" ]; then
        # THINLTO was the old name for LTO_THIN, and it was 'default y'
        scripts/config --file $out_path/.config \
        -e LTO_CLANG \
        -d LTO_NONE \
        -d LTO_CLANG_THIN \
        -e LTO_CLANG_FULL \
        -d THINLTO
    fi
    # Check and set BUILD_PROC environment variable
    local build_proc=${BUILD_PROC:-$(nproc)}
    make O=$out_path -j$build_proc
    set +x
    popd
    # restore path
    export PATH=$cache_path
}

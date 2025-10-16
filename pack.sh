#!/usr/bin/env bash
#
# pack_ddk_zst.sh — 打包 DDK 各目录为 .tar.zst
# 支持 CLI 参数：
#   -c, --clang       打包 clang/*
#   -s, --src         打包 src/*
#   -k, --kdir        打包 kdir/*
#   -v, --version     指定版本子目录名（如 r530983）
#   （不带参数则执行全部打包）
#

set -euo pipefail

ROOT="/opt/ddk"

THREADS=$(nproc 2>/dev/null || sysctl -n hw.ncpu || echo 4)
ZSTFLAGS="-10 -T${THREADS}"
TARFLAGS=(
  --sort=name
  --mtime='2025-01-01 UTC'
  --owner=0 --group=0 --numeric-owner
  --exclude-vcs
  --exclude='.git*'
)

pack_dir() {
    local prefix="$1" # src / kdir / clang
    local base_dir="$2" # 根目录
    local target_dir="$3" # 子目录名
    local out_dir="$(pwd)/prebuilts/$prefix"

    mkdir -p "$out_dir"

    local out_file
    if [[ "$prefix" == "clang" ]]; then
        out_file="${out_dir}/${target_dir}.tar.zst"
    else
        out_file="${out_dir}/${prefix}.${target_dir}.tar.zst"
    fi

    echo "→ Packing $base_dir/$target_dir → $(basename "$out_file")"
    tar "${TARFLAGS[@]}" -C "$base_dir" \
        -I "zstd ${ZSTFLAGS}" \
        -cf "$out_file" "$target_dir"
}

pack_group() {
    local prefix="$1"
    local version="$2"
    local base_dir="$ROOT/$prefix"

    echo "📦 Packing $prefix directories..."

    if [[ -n "$version" ]]; then
        local d="$base_dir/$version"
        if [[ -d "$d" ]]; then
            pack_dir "$prefix" "$base_dir" "$version"
        else
            echo "⚠️  Skipping $prefix: $version not found under $base_dir"
        fi
    else
        for d in "$base_dir"/*; do
            [[ -d "$d" ]] || continue
            pack_dir "$prefix" "$base_dir" "$(basename "$d")"
        done
    fi
}

main() {
    local do_src=false
    local do_kdir=false
    local do_clang=false
    local version=""

    if [[ $# -eq 0 ]]; then
        do_src=true
        do_kdir=true
        do_clang=true
    else
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -s|--src) do_src=true ;;
                -k|--kdir) do_kdir=true ;;
                -c|--clang) do_clang=true ;;
                -v|--version)
                    shift
                    version="${1:-}"
                    if [[ -z "$version" ]]; then
                        echo "❌ Error: --version needs a version name"
                        exit 1
                    fi
                    ;;
                *) echo "Unknown option: $1"; exit 1 ;;
            esac
            shift
        done
    fi

    echo "Using ${THREADS} threads for compression."
    echo

    $do_src && pack_group "src" "$version"
    $do_kdir && pack_group "kdir" "$version"
    $do_clang && pack_group "clang" "$version"

    echo
    echo "✅ All archives created successfully!"
}

main "$@"

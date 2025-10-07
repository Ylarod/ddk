#!/usr/bin/env bash
#
# pack_ddk_zst.sh — 打包 DDK 各目录为 .tar.zst
# 特性：
#   ✅ src/、kdir/ 各自输出 src.xxx.tar.zst / kdir.xxx.tar.zst
#   ✅ clang/ 输出 clang-rxxxxxx.tar.zst（不加 clang. 前缀）
#   ✅ 忽略 .git / .svn / .hg
#   ✅ 可复现打包（固定 mtime / UID / GID）
#   ✅ 自动多线程 zstd 压缩
#

set -euo pipefail

ROOT="/opt/ddk"

# 检测 CPU 核数
THREADS=$(nproc 2>/dev/null || sysctl -n hw.ncpu || echo 4)
ZSTFLAGS="-10 -T${THREADS}"
TARFLAGS=(
  --sort=name
  --mtime='2025-01-01 UTC'
  --owner=0 --group=0 --numeric-owner
  --exclude-vcs
  --exclude='.git*'
)

echo "📦 Packing DDK directories..."
echo "Using ${THREADS} threads for compression."
echo

pack_dir() {
    local prefix="$1"   # src / kdir / clang
    local base_dir="$2" # 根目录
    local target_dir="$3" # 子目录名
    local out_dir="$base_dir"

    local out_file
    if [[ "$prefix" == "clang" ]]; then
        # clang 不加前缀
        out_file="${out_dir}/${target_dir}.tar.zst"
    else
        # src / kdir 加前缀
        out_file="${out_dir}/${prefix}.${target_dir}.tar.zst"
    fi

    echo "→ Packing $base_dir/$target_dir → $(basename "$out_file")"
    tar "${TARFLAGS[@]}" -C "$base_dir" \
        -I "zstd ${ZSTFLAGS}" \
        -cf "$out_file" "$target_dir"
}

# 打包 src/*
for d in "$ROOT/src"/*; do
    [[ -d "$d" ]] || continue
    pack_dir "src" "$ROOT/src" "$(basename "$d")"
done

# 打包 kdir/*
for d in "$ROOT/kdir"/*; do
    [[ -d "$d" ]] || continue
    pack_dir "kdir" "$ROOT/kdir" "$(basename "$d")"
done

# 打包 clang/*
for d in "$ROOT/clang"/*; do
    [[ -d "$d" ]] || continue
    pack_dir "clang" "$ROOT/clang" "$(basename "$d")"
done

echo
echo "✅ All archives created successfully!"

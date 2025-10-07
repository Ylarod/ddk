#!/usr/bin/env bash
set -euo pipefail

# === 配置区域 ===
# 这里列出需要推送的完整镜像名（源 → 目标基础）
# 格式： "源镜像名 目标镜像前缀"
# 注意：不包含 tag，tag 会自动带上日期后缀
MAPPINGS=(
  "ghcr.io/ylarod/ddk docker.cnb.cool/ylarod/ddk/ddk"
  "ghcr.io/ylarod/ddk/clang docker.cnb.cool/ylarod/ddk/ddk-clang"
)

DATE="$(date +%Y%m%d)"

echo "🧩 Preparing to process mappings:"
for pair in "${MAPPINGS[@]}"; do
  echo "  - $pair"
done

# === 遍历每组映射 ===
for pair in "${MAPPINGS[@]}"; do
  read -r SRC_IMAGE DST_IMAGE <<<"$pair"

  # 获取源镜像的所有 tag
  TAGS=$(docker image ls --format '{{.Repository}}:{{.Tag}}' \
    | grep "^${SRC_IMAGE}:" \
    | grep -v "<none>" || true)

  if [ -z "$TAGS" ]; then
    echo "⚠️  No local tags found for ${SRC_IMAGE}"
    continue
  fi

  echo
  echo "🔹 Found tags for ${SRC_IMAGE}:"
  echo "$TAGS" | sed 's/^/   - /'

  for full_src in $TAGS; do
    tag="${full_src##*:}"
    new_tag="${tag}-${DATE}"
    full_dst="${DST_IMAGE}:${new_tag}"
    full_dst2="${DST_IMAGE}:${tag}"

    echo
    echo "==> Processing: ${full_src}"
    echo "     → New: ${full_dst}"
    echo "     → New: ${full_dst2}"

    docker tag "${full_src}" "${full_dst}"
    docker tag "${full_src}" "${full_dst2}"
    docker push "${full_dst}"
    docker push "${full_dst2}"
  done
done

echo
echo "✅ All images have been retagged and pushed."

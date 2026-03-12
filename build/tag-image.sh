#!/usr/bin/env bash
set -euo pipefail

# === 配置区域 ===
# 直接使用 cnb 镜像地址
IMAGES=(
  "docker.cnb.cool/ylarod/ddk/ddk"
  "docker.cnb.cool/ylarod/ddk/ddk-min"
  "docker.cnb.cool/ylarod/ddk/ddk-toolchain"
)

DATE="$(date +%Y%m%d)"

echo "🧩 Preparing to process images:"
for image in "${IMAGES[@]}"; do
  echo "  - $image"
done

# === 遍历每个镜像 ===
for image in "${IMAGES[@]}"; do

  # 获取镜像的所有 tag
  TAGS=$(docker image ls --format '{{.Repository}}:{{.Tag}}' \
    | grep "^${image}:" \
    | grep -v "<none>" || true)

  if [ -z "$TAGS" ]; then
    echo "⚠️  No local tags found for ${image}"
    continue
  fi

  echo
  echo "🔹 Found tags for ${image}:"
  echo "$TAGS" | sed 's/^/   - /'

  for full_src in $TAGS; do
    tag="${full_src##*:}"
    new_tag="${tag}-${DATE}"
    full_dst="${image}:${new_tag}"

    echo
    echo "==> Processing: ${full_src}"
    echo "     → New: ${full_dst}"

    docker tag "${full_src}" "${full_dst}"
    docker push "${full_dst}"
    docker push "${full_src}"
  done
done

echo
echo "✅ All images have been retagged and pushed."

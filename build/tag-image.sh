#!/usr/bin/env bash
set -euo pipefail

DATE="$(date +%Y%m%d)"

IMAGES=$(docker image ls --format "{{.Repository}}:{{.Tag}}" \
  | grep 'ghcr.io/ylarod/ddk' \
  | grep -v "<none>" )

for img in $IMAGES; do
  repo="${img%%:*}"
  tag="${img##*:}"
  new_tag="${tag}-${DATE}"
  new_img="${repo}:${new_tag}"

  echo "==> Tagging $img as $new_img"
  docker tag "$img" "$new_img"
  docker push "$new_img"
done

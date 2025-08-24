#!/usr/bin/env bash

for file in dockerfiles/Dockerfile*; do
  tag=$(basename "$file" | cut -d'.' -f2-)
  tag=${tag//$'\n'/}
  image="ghcr.io/ylarod/ddk:$tag"
  docker push "$image"
  echo "Pushed $image"
done
for file in dockerfiles/Dockerfile*; do
    tag=$(basename $file | cut -d'.' -f2- | tr -d '\n')
    echo "Export ddk:$tag to docker-ddk-$tag.tar.zst"
    docker save ddk:$tag > docker-ddk-$tag.tar
    zstd --rm docker-ddk-$tag.tar
    sha256sum docker-ddk-$tag.tar.zst > docker-ddk-$tag.tar.zst.sha256
done
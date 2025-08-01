for file in dockerfiles/Dockerfile*; do
    tag=$(basename $file | cut -d'.' -f2- | tr -d '\n')
    echo "Build $tag from $file"
    docker build -f $file -t ddk:$tag .
    docker save ddk:$tag | zstd > docker-ddk-$tag.tar.zst
    sha256sum docker-ddk-$tag.tar.zst > docker-ddk-$tag.tar.zst.sha256
done
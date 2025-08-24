for file in dockerfiles/Dockerfile*; do
    tag=$(basename $file | cut -d'.' -f2- | tr -d '\n')
    echo "Build $tag from $file"
    docker build -f $file -t ghcr.io/ylarod/ddk:$tag .
done
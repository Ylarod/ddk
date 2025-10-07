FROM ubuntu:25.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LANGUAGE=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
    git wget curl ca-certificates tar xz-utils \
    build-essential bc bison flex \
    libelf-dev libssl-dev \
    dwarves rsync python3 \
    lz4 zstd libncurses-dev \
    binutils-aarch64-linux-gnu file ccache \
  && rm -rf /var/lib/apt/lists/*

# Keep default entrypoint/cmd from base image (code-server already included)

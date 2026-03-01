FROM ubuntu:25.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LANGUAGE=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
    git git-lfs wget curl ca-certificates tar xz-utils \
    build-essential bc bison flex python3 clang lld \
    libelf-dev libssl-dev libdw-dev cpio \
    dwarves rsync python3 device-tree-compiler \
    lz4 zstd libncurses-dev bash jq \
    binutils-aarch64-linux-gnu file ccache \
    openssl libssl-dev dkms libelf-dev libudev-dev libpciaccess-dev libiberty-dev \
    zlib1g-dev libc6-dev-i386 lib32z1-dev \
    libx11-dev libgl1-mesa-dev \
    libxml2-utils xsltproc \
  && rm -rf /var/lib/apt/lists/*

RUN ln -sf /bin/bash /bin/sh
RUN ln -sf /usr/bin/python3 /usr/bin/python

# Keep default entrypoint/cmd from base image (code-server already included)

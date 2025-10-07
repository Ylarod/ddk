FROM ubuntu:25.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LANGUAGE=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
    git git-lfs wget curl ca-certificates tar xz-utils \
    build-essential bc bison flex \
    libelf-dev libssl-dev \
    dwarves rsync python3 \
    lz4 zstd libncurses-dev bash jq \
    binutils-aarch64-linux-gnu file ccache \
  && rm -rf /var/lib/apt/lists/*

RUN ln -sf /bin/bash /bin/sh

# Preinstall Android kernel Clang toolchains used by the pipeline
RUN set -eux; \
    mkdir -p /opt/ddk/clang; \
    cd /opt/ddk; \
    URL_PREFIX="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads"; \
    download() { branch="$1"; version="$2"; dest="clang/$version"; \
      if [ ! -d "$dest" ]; then \
        echo "[+] Fetching $version from $branch"; \
        wget -nv "$URL_PREFIX/$branch/$version.tar.gz" -O "$version.tar.gz"; \
        mkdir -p "$dest"; \
        tar xzf "$version.tar.gz" -C "$dest"; \
        rm -f "$version.tar.gz"; \
      else \
        echo "[!] $version already present, skipping"; \
      fi; \
    }; \
    download master-kernel-build-2021 clang-r416183b; \
    download master-kernel-build-2022 clang-r450784e; \
    download main-kernel-build-2023 clang-r487747c; \
    download main-kernel-build-2024 clang-r510928; \
    download main-kernel-2025 clang-r536225

# Keep default entrypoint/cmd from base image (code-server already included)

ARG VER
ARG CLANG_VER

FROM ghcr.io/ylarod/ddk-base:latest AS base
FROM ghcr.io/ylarod/ddk:${VER}

RUN --mount=type=bind,from=base,source=/opt/ddk/apt-archives,target=/mnt/debs,ro \
    set -eux; \
    apt-get install -y --no-install-recommends /mnt/debs/*.deb || apt-get -f install -y; \
    ln -sf "$(command -v python3)" /usr/local/bin/python; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /workspaces/ddk

LABEL org.opencontainers.image.title="ddk-dev" \
      org.opencontainers.image.description="Developer container image for ddk" \
      io.ddk.project="ddk" \
      io.ddk.variant="dev" \
      io.ddk.base.version="${VER}"

CMD ["/bin/bash"]
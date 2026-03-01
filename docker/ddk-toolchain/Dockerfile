FROM docker.cnb.cool/ylarod/ddk/ddk-builder:latest

WORKDIR /opt/ddk

ARG CLANG_VER
ARG RUST_VER=""

RUN --mount=type=bind,source=clang/${CLANG_VER}.tar.zst,target=/mnt/clang.tar.zst,readonly \
    mkdir -p /opt/ddk/clang/; \
    tar -I zstd -xf "/mnt/clang.tar.zst" -C "/opt/ddk/clang/";

RUN --mount=type=bind,source=rust/,target=/mnt/rust,readonly \
    set -eu; \
    if [ -n "${RUST_VER}" ] && [ -f "/mnt/rust/${RUST_VER}.tar.zst" ]; then \
      echo "[+] Importing rust ${RUST_VER}"; \
      mkdir -p /opt/ddk/rust/; \
      tar -I zstd -xf "/mnt/rust/${RUST_VER}.tar.zst" -C "/opt/ddk/rust/"; \
    fi

ENV DDK_ROOT=/opt/ddk \
    CLANG_PATH=/opt/ddk/clang/${CLANG_VER}/bin \
    RUST_PATH=/opt/ddk/rust/${RUST_VER}/bin \
    PATH=/opt/ddk/clang/${CLANG_VER}/bin:/opt/ddk/rust/${RUST_VER}/bin:$PATH

LABEL org.opencontainers.image.title="DDK toolchain ${CLANG_VER}" \
      org.opencontainers.image.description="DDK toolchain base image (Clang + Rust, offline)" \
      org.opencontainers.image.source="https://github.com/Ylarod/ddk" \
      org.opencontainers.image.documentation="https://github.com/Ylarod/ddk#readme" \
      org.opencontainers.image.url="https://github.com/Ylarod/ddk" \
      io.ddk.project="ddk" \
      io.ddk.clang.version="${CLANG_VER}" \
      io.ddk.rust.version="${RUST_VER}"

CMD ["/bin/bash"]

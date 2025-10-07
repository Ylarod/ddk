ARG CLANG_VER
FROM ghcr.io/ylarod/ddk/clang:${CLANG_VER}
ARG CLANG_VER

WORKDIR /opt/ddk

ARG ANDROID_VER
ARG VERSION="${ANDROID_VER}"
ARG REVISION
ARG CREATED
ARG REPOSITORY="https://github.com/Ylarod/ddk"
ARG HOMEPAGE="https://github.com/Ylarod/ddk"
ARG DOCUMENTATION="https://github.com/Ylarod/ddk#readme"
ARG ISSUES="https://github.com/Ylarod/ddk/issues"
ARG LICENSE="Apache-2.0"
ARG VENDOR="Ylarod"

LABEL org.opencontainers.image.title="DDK ${ANDROID_VER}" \
      org.opencontainers.image.description="Kernel Driver Development Kit for ${ANDROID_VER} (offline build)" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.created="${CREATED}" \
      org.opencontainers.image.url="${HOMEPAGE}" \
      org.opencontainers.image.source="${REPOSITORY}" \
      org.opencontainers.image.documentation="${DOCUMENTATION}" \
      org.opencontainers.image.licenses="${LICENSE}" \
      org.opencontainers.image.vendor="${VENDOR}" \
      io.ddk.project="ddk" \
      io.ddk.android.version="${ANDROID_VER}" \
      io.ddk.clang.version="${CLANG_VER}" \
      io.ddk.kernel.src="${ANDROID_VER}"

RUN --mount=type=bind,source=src/src.${ANDROID_VER}.tar,target=/tmp/src.tar,readonly \
    mkdir -p /opt/ddk/src/${ANDROID_VER} /opt/ddk/kdir/${ANDROID_VER}; \
    tar -xf /tmp/src.tar  -C /opt/ddk/src/${ANDROID_VER} --strip-components=1; \
    cd /opt/ddk/src/${ANDROID_VER} && make gki_defconfig && make modules_prepare;

ENV DDK_ROOT=/opt/ddk \
    CROSS_COMPILE=aarch64-linux-gnu- \
    ARCH=arm64 \
    LLVM=1 \
    LLVM_IAS=1 \
    KERNEL_SRC=/opt/ddk/src/${ANDROID_VER} \
    KDIR=/opt/ddk/src/${ANDROID_VER} \
    CLANG_PATH=/opt/ddk/clang/${CLANG_VER}/bin \
    PATH=/opt/ddk/clang/${CLANG_VER}/bin:$PATH

CMD ["/bin/bash"]

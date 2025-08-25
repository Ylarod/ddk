# Kernel Driver Development Kit (DDK)

This toolkit is designed for rapid kernel module development, but it **does not guarantee** full compatibility with the corresponding kernel version.

For perfect compatibility, you need to download the full kernel source code and compile it yourself. Refer to the relevant documentation for details.

If you prefer not to download Clang, you can use NDK Clang for compilation. However, the compiled output **might** have different structure offsets.

## Docker Image Usage (Recommended: Pull from GHCR)

Images are published to GitHub Container Registry (GHCR). It's recommended to pull images directly from GHCR instead of downloading large tar files from Releases:

```bash
# Pull image (example)
docker pull ghcr.io/ylarod/ddk:android12-5.10

docker run --rm -v /tmp/testko:/build -w /build ghcr.io/ylarod/ddk:android12-5.10 make
```

If older documentation or scripts mention downloading `.tar` and importing images, that is outdated — prefer `ghcr.io/ylarod/ddk:<ver>`.

### Build Modules

```bash
# x86 devices
docker run --rm -v /tmp/testko:/build -w /build ghcr.io/ylarod/ddk:android12-5.10 make

# M1 devices using Orbstack
docker run --rm -v /tmp/testko:/build -w /build --platform linux/amd64 ghcr.io/ylarod/ddk:android12-5.10 make
```

### Clean Build Artifacts

```bash
# x86 devices
docker run --rm -v /tmp/testko:/build -w /build ghcr.io/ylarod/ddk:android12-5.10 make clean

# M1 devices using Orbstack
docker run --rm -v /tmp/testko:/build -w /build --platform linux/amd64 ghcr.io/ylarod/ddk:android12-5.10 make clean
```

### Interactive Shell

```bash
# x86 devices
docker run -it --rm -v /tmp/testko:/build -w /build ghcr.io/ylarod/ddk:android12-5.10

# M1 devices using Orbstack
docker run -it --rm -v /tmp/testko:/build -w /build --platform linux/amd64 ghcr.io/ylarod/ddk:android12-5.10
```

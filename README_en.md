# Kernel Driver Development Kit (DDK)

This toolkit is designed for rapid kernel module development, but it **does not guarantee** full compatibility with the corresponding kernel version.

For perfect compatibility, you need to download the full kernel source code and compile it yourself. Refer to the relevant documentation for details.

If you prefer not to download Clang, you can use NDK Clang for compilation. However, the compiled output **might** have different structure offsets.

## Docker Image Usage (recommended)

This repository includes a convenient shell wrapper at `scripts/ddk` that wraps common Docker commands used with the DDK images.

Behavior highlights:
- The script mounts the current working directory into the container at `/build` and uses `/build` as the working directory.
- Docker platform is forced to `linux/amd64` to provide a consistent x86 toolchain.
- You can pass the image target as a positional argument or with `--target`/`-t`. If you omit the target, the script will use the `DDK_TARGET` environment variable. If neither is set, the script errors.

Examples:

```bash
# Pull image
./scripts/ddk pull android12-5.10

# Build in container (runs `make` in current dir)
./scripts/ddk build --target android12-5.10

# Pass make args
./scripts/ddk build --target android12-5.10 -- CFLAGS=-O2

# Use environment fallback
export DDK_TARGET=android12-5.10
./scripts/ddk build   # will use DDK_TARGET

# Clean
./scripts/ddk clean --target android12-5.10

# Interactive shell
./scripts/ddk shell --target android12-5.10
```

Make sure `scripts/ddk` is executable:

```bash
chmod +x scripts/ddk
```

## Docker Image Usage (LEGACY)

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

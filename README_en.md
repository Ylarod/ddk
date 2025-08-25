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

## About scripts and building images

Note: the `scripts/` directory no longer contains logic to build Docker images — image building is managed by the `docker/Makefile`.

If you only need to build images locally or in CI, use the `docker/Makefile` targets:

- Build/ensure clang toolchains:

```bash
make -C docker toolchains
```

- Build a single version (automatically packs src/kdir):

```bash
make -C docker build VER=android14-6.1
```

- Build all versions in the matrix:

```bash
make -C docker build-all
```

- Push during build (set `PUSH=1`) after logging in to GHCR:

```bash
# Login to GHCR
echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin

# Build and push
make -C docker build VER=android14-6.1 PUSH=1 PLAT=linux/amd64,linux/arm64
```

`make pack` writes `.pkg/src.<VER>.tar` and `.pkg/kdir.<VER>.tar`, which are used for offline or CI builds.

## How to Build the Toolkit

Clone the repo and run:

```sh
./setup.sh
```

After compilation, create modules by referring to `module_template`.

To build the DDK release, use `docker/Makefile` for automated builds and pushes.


### Quick verification of build correctness

```sh
cat kdir/android12-5.10/Module.symvers | grep module_layout
cat kdir/android13-5.15/Module.symvers | grep module_layout
cat kdir/android14-6.1/Module.symvers | grep module_layout
```

Compare outputs:

```
0x7c24b32d      module_layout   vmlinux EXPORT_SYMBOL
0x0222dd63      module_layout   vmlinux EXPORT_SYMBOL
0xea759d7f      module_layout   vmlinux EXPORT_SYMBOL
```

### Module Build Environment Initialization Script

```sh
export DDK_ROOT=/opt/ddk

# android12-5.10
export KERNEL_SRC=$DDK_ROOT/kdir/android12-5.10
export CLANG_PATH=$DDK_ROOT/clang/clang-r416183b/bin

# android13-5.15
# export KERNEL_SRC=$DDK_ROOT/kdir/android13-5.15
# export CLANG_PATH=$DDK_ROOT/clang/clang-r450784e/bin

# android14-6.1
# export KERNEL_SRC=$DDK_ROOT/kdir/android14-6.1
# export CLANG_PATH=$DDK_ROOT/clang/clang-r487747c/bin

export PATH=$CLANG_PATH:$PATH
export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64
export LLVM=1
export LLVM_IAS=1
```

### Adding a new version

For example, `android16-6.12`:

1. Check the kernel manifest: <https://android.googlesource.com/kernel/manifest/+/refs/heads/common-android16-6.12/default.xml>

```
<default revision="main-kernel-2025" remote="aosp" sync-j="4" />
```

Record `revision` as `main-kernel-2025`, which is the `clang_branch_name`.

2. Check the kernel configuration: <https://android.googlesource.com/kernel/common/+/refs/heads/android16-6.12/build.config.constants>

```
CLANG_VERSION=r536225
```

Record `CLANG_VERSION` as `clang_name`.

3. `source_name` is `android16-6.12`.

4. Edit `setup.sh` and `.github/workflows/release.yml` to add the new version.

5. Modify MATRIX (add the new entry in `docker/Makefile`'s MATRIX)

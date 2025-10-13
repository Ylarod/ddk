# Building DDK artifacts (toolkit)

This document describes how to build the toolkit artifacts used to produce the DDK release images and packaged kernel sources.

## Quick build (local)

Clone the repository and run:

```sh
./setup.sh
```

After compilation, create modules by referring to `module_template`.


### Quick verification of build correctness

```sh
cat /opt/ddk/kdir/android12-5.10/Module.symvers | grep module_layout
cat /opt/ddk/kdir/android13-5.15/Module.symvers | grep module_layout
cat /opt/ddk/kdir/android14-6.1/Module.symvers | grep module_layout
```

Compare outputs:

```
0x7c24b32d      module_layout   vmlinux EXPORT_SYMBOL
0x0222dd63      module_layout   vmlinux EXPORT_SYMBOL
0xea759d7f      module_layout   vmlinux EXPORT_SYMBOL
```

### Build docker images

To build the DDK release images (toolchain + runtime images), use the `docker/Makefile` automation:

- Build/ensure clang toolchains:

```bash
make -C docker toolchains
```

- Build a single DDK image (automatically packs src/kdir):

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
make -C docker build VER=android14-6.1 PUSH=1
```

- Build devcontainer images

```bash
make -C docker devcontainer-all PUSH=1
```
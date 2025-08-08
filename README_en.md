# Kernel Driver Development Kit (DDK)

This toolkit is designed for rapid kernel module development, but it **does not guarantee** full compatibility with the corresponding kernel version.

For perfect compatibility, you need to download the full kernel source code and compile it yourself. Refer to the relevant documentation for details.

If you prefer not to download Clang, you can use NDK Clang for compilation. However, the compiled output **might** have different structure offsets.

## Docker Image Usage Guide

Download and extract the image files from the [Release](https://github.com/Kernel-SU/ddk/releases/latest), then import the images:

```bash
docker pull ghcr.io/ylarod/ddk:android12-5.10
docker pull ghcr.io/ylarod/ddk:android13-5.10
docker pull ghcr.io/ylarod/ddk:android13-5.15
docker pull ghcr.io/ylarod/ddk:android14-5.15
docker pull ghcr.io/ylarod/ddk:android14-6.1
docker pull ghcr.io/ylarod/ddk:android15-6.6
docker pull ghcr.io/ylarod/ddk:android16-6.12
```

### Build Modules

```bash
# x86 devices
docker run --rm -v /tmp/testko:/build -w /build ddk:android12-5.10 make
```

### Clean Build Artifacts

```bash
# x86 devices
docker run --rm -v /tmp/testko:/build -w /build ddk:android12-5.10 make clean
```

### Interactive Shell

```bash
# x86 devices
docker run -it --rm -v /tmp/testko:/build -w /build ddk:android12-5.10
```

## How to Build the Toolkit

Clone the repository and execute:

```sh
./setup.sh
```

After compilation, you can create modules by referring to `module_template`.

To build the DDK release, refer to the scripts in the `scripts` directory.

### Simple Compilation Verification

```sh
cat kdir/android12-5.10/Module.symvers | grep module_layout
cat kdir/android13-5.15/Module.symvers | grep module_layout
cat kdir/android14-6.1/Module.symvers | grep module_layout
```

Compare the output:

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

### Kernel Module Makefile Example

```Makefile
MODULE_NAME := Shami
$(MODULE_NAME)-objs := core.o
obj-m := $(MODULE_NAME).o

ccflags-y += -Wno-declaration-after-statement
ccflags-y += -Wno-unused-variable
ccflags-y += -Wno-int-conversion
ccflags-y += -Wno-unused-result
ccflags-y += -Wno-unused-function
ccflags-y += -Wno-builtin-macro-redefined -U__FILE__ -D__FILE__='""'

KDIR := $(KERNEL_SRC)
MDIR := $(realpath $(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

$(info -- KDIR: $(KDIR))
$(info -- MDIR: $(MDIR))

all:
	make -C $(KDIR) M=$(MDIR) modules
compdb:
	python3 $(MDIR)/.vscode/generate_compdb.py -O $(KDIR) $(MDIR)
clean:
	make -C $(KDIR) M=$(MDIR) clean
```

### Configure Code Suggestions

Install the `clangd` plugin for VSCode.

Execute:

```sh
python3 .vscode/generate_compdb.py -O $DDK_ROOT/kdir/android14-6.1 .
```

Or simply:

```sh
make compdb
```

### Adding a New Version

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

5. Add a new `Dockerfile.android16-6.12` in the `dockerfiles` directory.

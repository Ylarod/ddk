# 内核驱动开发工具包 (Kernel Driver Development Kit)

该工具包旨在快速开发内核模块，但**不保证**内核模块能够完全兼容对应版本的内核。

如果需要完全兼容性，请下载完整内核代码并自行编译，具体方法请参考相关文档。

如果不想下载 Clang，可以使用 NDK Clang 进行编译，但**可能**会导致编译产物的结构体偏移有所不同。

## Docker 镜像使用教程（推荐：从 GHCR 拉取）

镜像已发布到 GitHub Container Registry（GHCR）。推荐直接从 GHCR 拉取镜像，而不是从 Release 下载大型 tar：

```bash
# 拉取镜像（示例）
docker pull ghcr.io/ylarod/ddk:android12-5.10

docker run --rm -v /tmp/testko:/build -w /build ghcr.io/ylarod/ddk:android12-5.10 make
```

如果你之前的文档或者脚本提到从 Release 下载并导入 `.tar`，那部分已过时：现在推荐直接从 `ghcr.io/ylarod/ddk:<ver>` 拉取。

### 构建模块

```bash
# x86 设备
docker run --rm -v /tmp/testko:/build -w /build ghcr.io/ylarod/ddk:android12-5.10 make

# M1 设备使用 Orbstack
docker run --rm -v /tmp/testko:/build -w /build --platform linux/amd64 ghcr.io/ylarod/ddk:android12-5.10 make
```

### 清理构建产物

```bash
# x86 设备
docker run --rm -v /tmp/testko:/build -w /build ghcr.io/ylarod/ddk:android12-5.10 make clean

# M1 设备使用 Orbstack
docker run --rm -v /tmp/testko:/build -w /build --platform linux/amd64 ghcr.io/ylarod/ddk:android12-5.10 make clean
```

### 进入交互式 Shell

```bash
# x86 设备
docker run -it --rm -v /tmp/testko:/build -w /build ghcr.io/ylarod/ddk:android12-5.10

# M1 设备使用 Orbstack
docker run -it --rm -v /tmp/testko:/build -w /build --platform linux/amd64 ghcr.io/ylarod/ddk:android12-5.10
```

## 关于脚本和镜像构建

注意：仓库内的 `scripts/` 目录**不再包含**构建 Docker 镜像的逻辑（构建由 `docker/Makefile` 管理）。如果你看到旧的 `scripts/build_docker_images.sh` 或 `scripts/prepare_release.sh`，请以 `docker/Makefile` 为准。

如果只需本地或 CI 构建镜像，推荐使用 `docker/Makefile` 提供的目标：

- 先构建/确保 clang toolchains：

```bash
make -C docker toolchains
```

- 然后为单个版本构建镜像（会自动打包 src/kdir）：

```bash
make -C docker build VER=android14-6.1
```

- 或构建矩阵中所有版本：

```bash
make -C docker build-all
```

- 若希望在构建时同时推送到 GHCR，请设置 `PUSH=1` 并先登录：

```bash
# 登录 GHCR
echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin

# 构建并推送
make -C docker build VER=android14-6.1 PUSH=1 PLAT=linux/amd64,linux/arm64
```

`make pack` 会在 `.pkg/` 生成 `src.<VER>.tar` 和 `kdir.<VER>.tar`，用于在 CI 或无网络环境下构建镜像。

## 工具包制作方法

克隆仓库后执行：

```sh
./setup.sh
```

编译完成后，可以参考 `module_template` 创建模块。

构建 DDK Release 可参考 `docker/Makefile` 自动化构建与推送。

### 简单校验编译正确性

```sh
cat kdir/android12-5.10/Module.symvers | grep module_layout
cat kdir/android13-5.15/Module.symvers | grep module_layout
cat kdir/android14-6.1/Module.symvers | grep module_layout
```

对比输出：

```
0x7c24b32d      module_layout   vmlinux EXPORT_SYMBOL
0x0222dd63      module_layout   vmlinux EXPORT_SYMBOL
0xea759d7f      module_layout   vmlinux EXPORT_SYMBOL
```

### 模块构建环境初始化脚本

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

### 内核模块 Makefile 示例

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

### 配置代码提示

安装 VSCode 的 `clangd` 插件。

执行：

```sh
python3 .vscode/generate_compdb.py -O $DDK_ROOT/kdir/android14-6.1 .
```

或者直接：

```sh
make compdb
```

### 添加新版本

以 `android16-6.12` 为例：

1. 查看内核清单：<https://android.googlesource.com/kernel/manifest/+/refs/heads/common-android16-6.12/default.xml>

```
<default revision="main-kernel-2025" remote="aosp" sync-j="4" />
```

记录 `revision` 为 `main-kernel-2025`，即 `clang_branch_name`。

2. 查看内核配置：<https://android.googlesource.com/kernel/common/+/refs/heads/android16-6.12/build.config.constants>

```
CLANG_VERSION=r536225
```

记录 `CLANG_VERSION` 为 `clang_name`。

3. `source_name` 为 `android16-6.12`。

4. 编辑 `setup.sh` 和 `.github/workflows/release.yml`，添加新版本。

5. 修改 MATRIX（在 `docker/Makefile` 中添加新条目）

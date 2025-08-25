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
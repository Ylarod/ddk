# DDK Docker 镜像

## 镜像概览

| 镜像 | Dockerfile | 说明 |
|------|-----------|------|
| `ddk-builder` | `ddk-builder/Dockerfile` | 基础构建环境，包含 GCC/Clang/内核构建依赖 |
| `ddk-toolchain` | `ddk-toolchain/Dockerfile` | 工具链镜像，预装 Clang 和可选的 Rust 工具链 |
| `ddk` | `ddk/Dockerfile` | 完整 DDK 镜像，包含内核源码和预编译 kdir |
| `ddk-cnb-dev` | `ddk-cnb-dev/Dockerfile` | CNB 云开发环境，附带 code-server 和全部 Clang 工具链 |
| ~~`ddk-clang`~~ | — | **已弃用**，由 `ddk-toolchain` 替代 |

## 依赖关系

```
ubuntu:25.04
└── ddk-builder
    ├── ddk-toolchain:{ANDROID_VER} (Clang + 可选 Rust)
    │   └── ddk:{ANDROID_VER}
    └── ddk-cnb-dev
```

- **ddk-builder** 基于 `ubuntu:25.04`，安装编译内核所需的全部系统依赖
- **ddk-toolchain** 基于 `ddk-builder`，解压并配置 Clang 工具链，android16-6.12 起同时包含 Rust 工具链
- **ddk** 基于 `ddk-toolchain`，打包特定 Android 版本的内核源码和预编译 kdir
- **ddk-cnb-dev** 基于 `ddk-builder`，加装全部 Clang 工具链和 code-server，用于 CNB 通用云开发

## 构建命令

所有构建通过 `docker/Makefile` 驱动，在仓库根目录执行：

```bash
# 构建 ddk-builder 基础镜像
make -C docker builder

# 构建所有工具链镜像（Clang + 可选 Rust）
make -C docker toolchains

# 构建单个 DDK 镜像
make -C docker build VER=android14-6.1

# 构建全部 DDK 镜像
make -C docker build-all

# 构建 ddk-cnb-dev 开发镜像
make -C docker cnb-dev
```

构建时添加 `PUSH=1` 可直接推送到远程仓库，添加 `REG=<registry>` 可覆盖默认镜像仓库地址：

```bash
# 登录 GHCR
echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin

# 构建并推送
make -C docker build VER=android14-6.1 PUSH=1 REG=ghcr.io/ylarod/ddk
```

## 本地快速构建

克隆仓库后直接执行：

```bash
bash build/setup.sh
```

编译完成后参考 `module_template` 创建内核模块。

### 验证构建产物

```bash
cat /opt/ddk/kdir/android12-5.10/Module.symvers | grep module_layout
cat /opt/ddk/kdir/android13-5.15/Module.symvers | grep module_layout
cat /opt/ddk/kdir/android14-6.1/Module.symvers | grep module_layout
```

预期输出（CRC 值因版本而异）：

```
0x7c24b32d      module_layout   vmlinux EXPORT_SYMBOL
0x0222dd63      module_layout   vmlinux EXPORT_SYMBOL
0xea759d7f      module_layout   vmlinux EXPORT_SYMBOL
```

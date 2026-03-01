# 内核驱动开发工具包 (Kernel Driver Development Kit)

[English](README_en.md) | 简体中文

该工具包旨在快速开发内核模块，但**不保证**内核模块能够完全兼容对应版本的内核。

如果需要完全兼容性，请下载完整内核代码并自行编译，具体方法请参考相关文档。

如果不想下载 Clang，可以使用 NDK Clang 进行编译，但**可能**会导致编译产物的结构体偏移有所不同。

submodule 下的 prebuilts tarball 文件很大，非必要不要 clone submodules

内核模块开发模板：

[Github](https://github.com/Ylarod/ddk-module-template)

[CNB](https://cnb.cool/Ylarod/ddk-module-template)

## 选择开发模式

| 场景 | 推荐模式 |
|---|---|
| Linux 本机开发 | **Host 模式**（推荐） |
| macOS / Windows 开发 | **DevContainer 模式**（推荐） |
| CI / 自动化构建 | **Docker 模式** |

---

## Host 模式（推荐 Linux 用户）

> [!NOTE]
> Host 模式将内核源码和 Clang 工具链直接解压到 `/opt/ddk` 目录，无需 Docker 或容器环境，是 Linux 用户的首选开发方式。

### 前置依赖

- `git-lfs`（用于拉取 submodule 中的大文件，**必须在克隆前安装并初始化**）
- `zstd`（用于解压 `.tar.zst` 归档文件）
- `jq`（用于 VSCode 配置脚本）

安装并启用 Git LFS：

```bash
# Debian/Ubuntu
sudo apt install git-lfs
# Arch
sudo pacman -S git-lfs

git lfs install
```

### 安装步骤

#### 1. 克隆仓库（含 submodules）

> [!WARNING]
> `prebuilts` submodule 中包含大量通过 Git LFS 存储的预编译归档文件，体积较大，请确保已安装 `git-lfs` 并有足够的磁盘空间和网络带宽。

```bash
git clone --recurse-submodules https://github.com/Ylarod/ddk.git
cd ddk
```

如果已经克隆但未初始化 submodule：

```bash
git submodule update --init --recursive
```

#### 2. 运行安装脚本

```bash
bash host/install.sh
```

安装脚本会将 `prebuilts/` 中的内核源码（`src`）、编译头文件（`kdir`）和 Clang 工具链（`clang`）解压到 `/opt/ddk`：

```
/opt/ddk/
├── src/          # 各 Android 版本内核源码
│   ├── android12-5.10/
│   ├── android13-5.10/
│   └── ...
├── kdir/         # 各 Android 版本编译头文件
└── clang/        # Clang 工具链
```

#### 3. 配置 VSCode clangd 代码索引

首先确保 `~/.ddk/mapping.json` 存在（从仓库根目录的 `mapping.json` 复制）：

```bash
mkdir -p ~/.ddk
cp mapping.json ~/.ddk/mapping.json
```

然后运行配置脚本：

```bash
bash host/vscode_clangd_configure.sh
```

该脚本会：
- 读取 `~/.ddk/mapping.json` 获取 Android 版本与 Clang 版本的对应关系
- 将 `host/.vscode` 模板（含文件过滤规则、编辑器设置、`compile_commands.json` 生成脚本等）复制到每个 `/opt/ddk/src/<android-version>/` 目录
- 配置各目录下 `.vscode/settings.json` 中的 `clangd.path`，指向对应版本的 Clang

支持 `--dry-run` 参数预览操作：

```bash
bash host/vscode_clangd_configure.sh --dry-run
```

#### 4. 在 VSCode 中打开内核源码

用 VSCode 打开对应的内核源码目录，安装 [clangd 扩展](https://marketplace.visualstudio.com/items?itemName=llvm-vs-code-extensions.vscode-clangd) 后即可获得代码补全、跳转、引用查找等功能：

```bash
code /opt/ddk/src/android16-6.12
```

---

## DevContainer 模式（推荐 macOS / Windows 用户）

> [!TIP]
> 对于中国大陆用户，可以使用 `docker.cnb.cool/ylarod/ddk/ddk` 来代替 `ghcr.io/ylarod/ddk`

DevContainer 通过容器提供与平台无关的一致开发环境，适合无法直接使用 Host 模式的 macOS 或 Windows 用户。

### 本地 DevContainer

> [!WARNING]
> 当你使用这个方法的时候，你必须手动 `source envsetup.sh`

把下面内容放置到 `.devcontainer/devcontainer.json`。

可以修改 features 的内容来自由组装想要的镜像，可以选择的版本参考 [ddk image versions](https://github.com/Ylarod/ddk/pkgs/container/ddk/versions)

参考：

- [ddk-toolchain](https://github.com/Ylarod/ddk/blob/main/features/src/ddk-toolchain/devcontainer-feature.json)
- [ddk-src](https://github.com/Ylarod/ddk/blob/main/features/src/ddk-src/devcontainer-feature.json)

对于 M1 Mac + OrbStack 用户，参考 [ddk-module-template](https://github.com/Ylarod/ddk-module-template) 中的 `.devcontainer` 配置可以开发，还需要提前拉取镜像：

```bash
docker run --platform linux/amd64 --rm -it docker.cnb.cool/ylarod/ddk/ddk-builder:latest
```

对于 x86_64 用户：

```yml
{
  "name": "ddk-module-dev",
  "image": "docker.cnb.cool/ylarod/ddk/ddk-builder:latest",
  "features": {
    "ghcr.io/ylarod/ddk/features/ddk-toolchain:latest": {
      "androidVer": "android12-5.10",
      "setDefault": true
    },
    "ghcr.io/ylarod/ddk/features/ddk-src:latest": {
      "androidVer": "android12-5.10",
      "withKdir": true,
      "setDefault": true
    }
  },
  "remoteUser": "root",
  "postCreateCommand": "echo Devcontainer ready",
  "customizations": {
    "vscode": {
      "extensions": [
        "github.copilot",
        "github.copilot-chat",
        "github.vscode-github-actions",
        "llvm-vs-code-extensions.vscode-clangd",
        "ms-azuretools.vscode-containers",
        "ms-azuretools.vscode-docker",
        "ms-ceintl.vscode-language-pack-zh-hans"
      ]
    }
  }
}
```

### Github Codespaces 云开发

把下面内容放置到 `.devcontainer/devcontainer.json`。

可以修改 image 的内容来选择对应的版本开发，可以选择的版本参考 [ddk image versions](https://github.com/Ylarod/ddk/pkgs/container/ddk/versions)

```yaml
{
  "name": "ddk-module-dev",
  "image": "ghcr.io/ylarod/ddk:android16-6.12",
  "remoteUser": "root",
  "postCreateCommand": "echo Devcontainer ready",
  "customizations": {
    "vscode": {
      "extensions": [
        "github.copilot",
        "github.copilot-chat",
        "github.vscode-github-actions",
        "llvm-vs-code-extensions.vscode-clangd",
        "ms-azuretools.vscode-containers",
        "ms-azuretools.vscode-docker",
        "ms-ceintl.vscode-language-pack-zh-hans"
      ]
    }
  }
}
```

---

## Docker 模式（适合 CI / 自动化构建）

> [!NOTE]
> Docker 模式通过封装好的镜像直接构建，适合 CI 流水线和自动化场景，不推荐作为日常交互式开发环境。

### 本地使用 Docker 镜像

推荐先安装便捷脚本 `ddk`（封装常用 docker 命令，强制 `--platform linux/amd64` 并将当前目录挂载为容器内的 `/build`）。

安装（macOS/Linux）：

```bash
# 将 ddk 安装到 /usr/local/bin 并赋予可执行权限
sudo curl -fsSL https://raw.githubusercontent.com/Ylarod/ddk/main/scripts/ddk -o /usr/local/bin/ddk
sudo chmod +x /usr/local/bin/ddk
```

用法示例：

```bash
# 拉取镜像
ddk pull android12-5.10

# 进入项目目录
cd /path/to/source

# 构建
ddk build --target android12-5.10

# 传递 make 参数
ddk build --target android12-5.10 -- CFLAGS=-O2

# 清理
ddk clean --target android12-5.10

# 交互式 shell
ddk shell --target android12-5.10
```

如果你不想在每次命令中传入 target，可以设置环境变量 `DDK_TARGET`：

```bash
export DDK_TARGET=android12-5.10
ddk build   # 会使用 DDK_TARGET
```

### Github CI

参考下面的文件构建：

- 通用 Matrix 构建模板：[ddk-lkm.yml](https://github.com/Ylarod/ddk/blob/main/.github/workflows/ddk-lkm.yml)
- Module Template 构建：[module.yml](https://github.com/Ylarod/ddk/blob/main/.github/workflows/module.yml)

---

## 致谢

- 感谢 [cnb.cool](https://cnb.cool) 提供的 [计算资源](https://mp.weixin.qq.com/s/4VqdKrvsoidAokKArMZfQA)

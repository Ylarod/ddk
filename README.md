# 内核驱动开发工具包 (Kernel Driver Development Kit)

[English](README_en.md) | 简体中文

该工具包旨在快速开发内核模块，但**不保证**内核模块能够完全兼容对应版本的内核。

如果需要完全兼容性，请下载完整内核代码并自行编译，具体方法请参考相关文档。

如果不想下载 Clang，可以使用 NDK Clang 进行编译，但**可能**会导致编译产物的结构体偏移有所不同。

submodule 下的 prebuilts tarball 文件很大，非必要不要 clone submodules

## 使用方法

> [!TIP]
> 对于中国大陆用户，可以使用 docker.cnb.cool/ylarod/ddk/ddk 来代替 ghcr.io/ylarod/ddk

## 本地部署 Dev Container 开发环境

把下面内容放置到 .devcontainer/devcontainer.json

可以修改 features 的内容来自由组装想要的镜像，可以选择的版本参考 [ddk image versions](https://github.com/Ylarod/ddk/pkgs/container/ddk/versions)

参考：

- [ddk-clang](https://github.com/Ylarod/ddk/blob/main/features/src/ddk-clang/devcontainer-feature.json)
- [ddk-src](https://github.com/Ylarod/ddk/blob/main/features/src/ddk-src/devcontainer-feature.json)

```yml
{
  "name": "ddk-module-dev",
  "image": "docker.cnb.cool/ylarod/ddk/ddk-builder:latest",
  "features": {
    "ghcr.io/ylarod/ddk/features/ddk-clang:latest": {
      "clangVer": "clang-r416183b",
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

### Github Codespaces 云开发

把下面内容放置到 .devcontainer/devcontainer.json

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

## 致谢

- 感谢 [cnb.cool](https://cnb.cool) 提供的 [计算资源](https://mp.weixin.qq.com/s/4VqdKrvsoidAokKArMZfQA)

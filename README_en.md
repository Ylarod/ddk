# Kernel Driver Development Kit (DDK)

English | [简体中文](README.md)

This toolkit aims to speed up kernel module development, but it **does not guarantee** that modules will be fully compatible with the corresponding kernel version.

If you need full compatibility, please download the complete kernel source and compile it yourself; see relevant documentation for details.

If you prefer not to download Clang, you can use NDK Clang to build, but this **may** lead to different struct offsets in the compiled artifacts.

Prebuilts tarball in submodule is very large，do not clone submodules if unnecessary.

## Usage

> [!TIP]
> For users in Mainland China, you can use `docker.cnb.cool/ylarod/ddk/ddk` as a replacement for `ghcr.io/ylarod/ddk`.

### Local Dev Container Development Environment

Place the following content in `.devcontainer/devcontainer.json`.

You can modify the `features` to assemble the image you need. Available versions: [ddk image versions](https://github.com/Ylarod/ddk/pkgs/container/ddk/versions)

References:

- [ddk-clang](https://github.com/Ylarod/ddk/blob/main/features/src/ddk-clang/devcontainer-feature.json)
- [ddk-src](https://github.com/Ylarod/ddk/blob/main/features/src/ddk-src/devcontainer-feature.json)

For users with M1 Mac + orbstack, Ref to `module_template/.devcontainer`, and pull image in advance.

```bash
docker run --platform linux/amd64 --rm -it docker.cnb.cool/ylarod/ddk/ddk-builder:latest
```

For x86_64 users:

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


### Local Docker Image Usage

It is recommended to install the convenience script `ddk` first (wraps common docker commands, enforces `--platform linux/amd64`, and mounts the current directory to `/build` in the container).

Install (macOS/Linux):

```bash
# Install ddk to /usr/local/bin and make it executable
sudo curl -fsSL https://raw.githubusercontent.com/Ylarod/ddk/main/scripts/ddk -o /usr/local/bin/ddk
sudo chmod +x /usr/local/bin/ddk
```

Usage examples:

```bash
# Pull image
ddk pull android12-5.10

# Enter project directory
cd /path/to/source

# Build
ddk build --target android12-5.10

# Pass make arguments
ddk build --target android12-5.10 -- CFLAGS=-O2

# Clean
ddk clean --target android12-5.10

# Interactive shell
ddk shell --target android12-5.10
```

If you don't want to pass `--target` every time, set the `DDK_TARGET` environment variable:

```bash
export DDK_TARGET=android12-5.10
ddk build   # Will use DDK_TARGET
```

### GitHub CI

Refer to the following workflow files to build:

- Generic Matrix build template: [ddk-lkm.yml](https://github.com/Ylarod/ddk/blob/main/.github/workflows/ddk-lkm.yml)
- Module Template build: [module.yml](https://github.com/Ylarod/ddk/blob/main/.github/workflows/module.yml)

### GitHub Codespaces Cloud Development

Place the following content in `.devcontainer/devcontainer.json`.

You can modify the `image` value to pick the desired version for development. Available versions: [ddk image versions](https://github.com/Ylarod/ddk/pkgs/container/ddk/versions)

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

## Acknowledgments

- Thanks to [cnb.cool](https://cnb.cool) for providing [computing resources](https://mp.weixin.qq.com/s/4VqdKrvsoidAokKArMZfQA)

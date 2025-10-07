# Kernel Driver Development Kit

This toolkit is designed for rapid kernel module development, but **does not guarantee** that kernel modules will be fully compatible with the corresponding kernel version.

If you require full compatibility, please download the complete kernel source code and compile it yourself. Refer to the relevant documentation for specific instructions.

If you prefer not to download Clang, you can use NDK Clang for compilation, but this **may** result in differences in struct offsets in the compiled artifacts.

## Usage

## Local Dev Container Development Environment

Place the following content in `.devcontainer/devcontainer.json`

You can modify the features content to freely assemble the desired image. Available versions can be found at [ddk image versions](https://github.com/Ylarod/ddk/pkgs/container/ddk/versions)

References:

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


### Local Docker Image Usage

The repository includes a convenience script `scripts/ddk` that wraps common docker commands, enforcing `--platform linux/amd64` and mounting the current directory to `/build` in the container:

Usage examples:

```bash
# Pull image
./scripts/ddk pull android12-5.10

# Build
./scripts/ddk build --target android12-5.10

# Pass make arguments
./scripts/ddk build --target android12-5.10 -- CFLAGS=-O2

# Clean
./scripts/ddk clean --target android12-5.10

# Interactive shell
./scripts/ddk shell --target android12-5.10
```

If you don't want to specify target in every command, you can set the `DDK_TARGET` environment variable:

```bash
export DDK_TARGET=android12-5.10
./scripts/ddk build   # Will use DDK_TARGET
```

### GitHub CI

Refer to the following files for building:

- Generic Matrix build template: [ddk-lkm.yml](https://github.com/Ylarod/ddk/blob/main/.github/workflows/ddk-lkm.yml)
- Module Template build: [module.yml](https://github.com/Ylarod/ddk/blob/main/.github/workflows/module.yml)

### GitHub Codespaces Cloud Development

Place the following content in `.devcontainer/devcontainer.json`

You can modify the image content to select the corresponding version for development. Available versions can be found at [ddk image versions](https://github.com/Ylarod/ddk/pkgs/container/ddk/versions)

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

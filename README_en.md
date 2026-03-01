# Kernel Driver Development Kit (DDK)

English | [简体中文](README.md)

This toolkit aims to speed up kernel module development, but it **does not guarantee** that modules will be fully compatible with the corresponding kernel version.

If you need full compatibility, please download the complete kernel source and compile it yourself; see relevant documentation for details.

If you prefer not to download Clang, you can use NDK Clang to build, but this **may** lead to different struct offsets in the compiled artifacts.

Prebuilts tarball in submodule is very large, do not clone submodules if unnecessary.

Kernel module development template:

[Github](https://github.com/Ylarod/ddk-module-template)

[CNB](https://cnb.cool/Ylarod/ddk-module-template)

## Choose a Development Mode

| Scenario | Recommended Mode |
|---|---|
| Linux native development | **Host Mode** (Recommended) |
| macOS / Windows development | **DevContainer Mode** (Recommended) |
| CI / automated builds | **Docker Mode** |

---

## Host Mode (Recommended for Linux Users)

> [!NOTE]
> Host mode extracts the kernel source and Clang toolchain directly into `/opt/ddk`, requiring no Docker or container environment. It is the preferred development approach for Linux users.

### Prerequisites

- `git-lfs` (required to pull large files from the submodule — **must be installed and initialized before cloning**)
- `zstd` (for extracting `.tar.zst` archives)
- `jq` (for the VSCode configuration script)

Install and enable Git LFS:

```bash
# Debian/Ubuntu
sudo apt install git-lfs
# Arch
sudo pacman -S git-lfs

git lfs install
```

### Installation

#### 1. Clone the repository (with submodules)

> [!WARNING]
> The `prebuilts` submodule contains large pre-built archives stored via Git LFS. Make sure `git-lfs` is installed and you have sufficient disk space and bandwidth before proceeding.

```bash
git clone --recurse-submodules https://github.com/Ylarod/ddk.git
cd ddk
```

If you already cloned without initializing submodules:

```bash
git submodule update --init --recursive
```

#### 2. Run the install script

```bash
bash host/install.sh
```

The script extracts kernel sources (`src`), build headers (`kdir`), and the Clang toolchain (`clang`) from `prebuilts/` into `/opt/ddk`:

```
/opt/ddk/
├── src/          # Kernel sources for each Android version
│   ├── android12-5.10/
│   ├── android13-5.10/
│   └── ...
├── kdir/         # Build headers for each Android version
└── clang/        # Clang toolchain
```

#### 3. Configure VSCode clangd indexing

First ensure `~/.ddk/mapping.json` exists (copy from the repo root):

```bash
mkdir -p ~/.ddk
cp mapping.json ~/.ddk/mapping.json
```

Then run the configuration script:

```bash
bash host/vscode_clangd_configure.sh
```

The script will:
- Read `~/.ddk/mapping.json` to get the mapping between Android versions and Clang versions
- Copy the `host/.vscode` template (file filters, editor settings, `compile_commands.json` generator, etc.) into each `/opt/ddk/src/<android-version>/` directory
- Set `clangd.path` in each directory's `.vscode/settings.json` to point to the corresponding Clang binary

Use `--dry-run` to preview actions without making changes:

```bash
bash host/vscode_clangd_configure.sh --dry-run
```

#### 4. Open kernel source in VSCode

Open the desired kernel source directory in VSCode and install the [clangd extension](https://marketplace.visualstudio.com/items?itemName=llvm-vs-code-extensions.vscode-clangd) to get code completion, jump-to-definition, and reference search:

```bash
code /opt/ddk/src/android16-6.12
```

---

## DevContainer Mode (Recommended for macOS / Windows Users)

> [!TIP]
> For users in Mainland China, you can use `docker.cnb.cool/ylarod/ddk/ddk` as a replacement for `ghcr.io/ylarod/ddk`.

DevContainer provides a consistent, platform-independent development environment via containers, and is the recommended approach for macOS or Windows users who cannot use Host mode directly.

### Local DevContainer

> [!WARNING]
> You must `source envsetup.sh` when you use this method.

Place the following content in `.devcontainer/devcontainer.json`.

You can modify the `features` to assemble the image you need. Available versions: [ddk image versions](https://github.com/Ylarod/ddk/pkgs/container/ddk/versions)

References:

- [ddk-toolchain](https://github.com/Ylarod/ddk/blob/main/features/src/ddk-toolchain/devcontainer-feature.json)
- [ddk-src](https://github.com/Ylarod/ddk/blob/main/features/src/ddk-src/devcontainer-feature.json)

For M1 Mac + OrbStack users, refer to the `.devcontainer` configuration in [ddk-module-template](https://github.com/Ylarod/ddk-module-template) and pull the image in advance:

```bash
docker run --platform linux/amd64 --rm -it docker.cnb.cool/ylarod/ddk/ddk-builder:latest
```

For x86_64 users:

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

---

## Docker Mode (For CI / Automated Builds)

> [!NOTE]
> Docker mode builds directly with pre-built images and is suited for CI pipelines and automated workflows. It is not recommended as a daily interactive development environment.

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

---

## Acknowledgments

- Thanks to [cnb.cool](https://cnb.cool) for providing [computing resources](https://mp.weixin.qq.com/s/4VqdKrvsoidAokKArMZfQA)

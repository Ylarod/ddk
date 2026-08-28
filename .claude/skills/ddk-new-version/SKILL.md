---
name: ddk-new-version
description: Add or bump an Android GKI kernel version in the DDK repo (e.g. android17-6.18). Resolves the upstream manifest / clang / rust / bindgen versions from android.googlesource.com, updates mapping.json, then runs the real download + kernel build + prebuilt packing on the CNB build server over SSH. Use whenever asked to "适配新版本", add a new androidNN-X.Y target, or refresh a toolchain version.
---

# DDK 新版本适配

整条流水线由 `mapping.json` 驱动：`build/build-ddk.py` 下载工具链/源码并编译内核，
`build/pack.sh` 把 `/opt/ddk/*` 打成 `.tar.zst` 放进 `prebuilts/`（ddk-prebuilts 仓库），
`docker/Makefile` 再用这些 tarball 构建镜像。

**下载、编译、打包一律在 CNB 服务器上做，本地只改文件。** 用 `CNB=true` 标记
"我在 CNB 服务器上"，本地不设。

单个版本全程约 40 分钟（下载 ~10 min，编译 ~15 min，打包 ~3 min）。

---

## 步骤 0：本地铁律

`prebuilts/` 是 git-lfs 子模块，单个包动辄 1 GB。本地任何 git 操作都必须加
`GIT_LFS_SKIP_SMUDGE=1`，只保留 LFS 指针（134 字节）：

```bash
GIT_LFS_SKIP_SMUDGE=1 git pull
GIT_LFS_SKIP_SMUDGE=1 git submodule update --init --depth 1
```

确认没被污染：`ls -l prebuilts/clang/` 里的文件应该都是一百多字节。

---

## 步骤 1：确定上游版本

设 `NEW=android17-6.18`，`BR=${NEW}-lts`。

1. **manifest 的 default revision** —— 决定 clang / rust / clang-tools 看哪个分支：

   ```bash
   curl -s "https://android.googlesource.com/kernel/manifest/+/refs/heads/common-${BR}/default.xml?format=TEXT" | base64 -d
   ```

   看 `<default revision="..."/>`，android17-6.18 → `main-kernel-2026`。
   同时核对这几行的仓库名（rust 仓库换过位置，必须看，别照抄旧的）：

   ```xml
   <project path="prebuilts/clang/host/linux-x86"     name="platform/prebuilts/clang/host/linux-x86" .../>
   <project path="prebuilts/rust-toolchain/linux-x86" name="platform/prebuilts/rust-toolchain/linux-x86" .../>
   <project path="prebuilts/clang-tools"              name="platform/prebuilts/clang-tools" .../>
   ```

2. **工具链版本号** —— 内核树里的 `bazel/constants.scl`：

   ```bash
   curl -s "https://android.googlesource.com/kernel/common/+/refs/heads/${BR}/bazel/constants.scl?format=TEXT" | base64 -d
   ```

   取 `CLANG_VERSION`（如 `r584948c`）和 `RUSTC_VERSION`（如 `1.91.1.p3`）。
   **rust 带 `.pN` 后缀时要连后缀一起用**，上游目录名就叫 `1.91.1.p3`。

3. **确认预编译目录存在**（都必须 200，否则分支或版本号取错了）：

   ```bash
   REV=main-kernel-2026
   curl -so /dev/null -w "clang %{http_code}\n" "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+/refs/heads/$REV/clang-r584948c/?format=JSON"
   curl -so /dev/null -w "rust  %{http_code}\n" "https://android.googlesource.com/platform/prebuilts/rust-toolchain/linux-x86/+/refs/heads/$REV/1.91.1.p3/?format=JSON"
   ```

4. **确认 modpost 的几个补丁点还在**：

   ```bash
   curl -s "https://android.googlesource.com/kernel/common/+/refs/heads/${BR}/scripts/mod/modpost.c?format=TEXT" | base64 -d \
     | grep -n 'static void check_exports(\|check_exports(mod);\|s->module = exp->module;\|__version_ext_names\\") ='
   ```

用 gitiles 的 `?format=JSON` 列目录时记得 `sed '1d'` 去掉 `)]}'` 前缀行。

---

## 步骤 2：改 `mapping.json`

四处都要加，缺一不可：

```jsonc
"clang": [ ..., { "version": "clang-r584948c", "branch": "main-kernel-2026" } ],
"rust":  [ ..., { "version": "rust-1.91.1.p3", "branch": "main-kernel-2026",
                  "repo": "platform/prebuilts/rust-toolchain/linux-x86" } ],
"android": [ ..., { "name": "android17-6.18", "branch": "android17-6.18-lts" } ],
"matrix":  [ ..., { "android": "android17-6.18", "clang": "clang-r584948c",
                    "rust": "rust-1.91.1.p3" } ]
```

约定：`clang.version` 带 `clang-` 前缀，`rust.version` 带 `rust-` 前缀，
`build-ddk.py` 会 `removeprefix("rust-")` 再拼下载 URL。
老的 `platform/prebuilts/rust` 仓库要额外拼 `linux-x86/` 子路径，脚本按 `repo` 字段区分。
bindgen 不进 mapping.json —— 它跟着 rust 条目的 `branch` 走（见下）。

改完校验：`python3 -c "import json;json.load(open('mapping.json'))"`。

---

## 步骤 3：改 `build/build-ddk.py`

### 3.1 CFI

GKI 从 android16-6.12 起用 `-fsanitize-cfi-icall-experimental-normalize-integers` 编译，
但 `gki_defconfig` 里没这一项，必须手动打开，否则外部模块加载时 CFI 校验失败：

```python
CFI_NORMALIZE_INTEGERS_BRANCHES = {"android16-6.12", "android17-6.18"}
```

6.18 起 `CONFIG_CFI_CLANG` 改名成 `CONFIG_CFI`，但 `CONFIG_CFI_ICALL_NORMALIZE_INTEGERS`
和 `LTO_CLANG*` 名字都没变。构建后确认 `.config` 里有
`CONFIG_CFI_ICALL_NORMALIZE_INTEGERS=y`。

### 3.2 modpost 补丁（`patch_modpost`，4 条 sed）

前两条是 DDK 原有意图：放开符号校验、让 `depends` 为空。后两条是前两条的后果，
换新内核/新 clang 时最容易在这里翻车：

| sed | 作用 |
|---|---|
| 注释 `check_exports(mod);` | 允许引用不在 Module.symvers 里的符号 |
| 注释 `s->module = exp->module;` | 让 `MODULE_INFO(depends, "")` 为空 |
| `check_exports` 定义加 `__attribute__((unused))` | 上一条让它成了未使用 static 函数，clang-r584948c 起 `-Wunused-function` 是 `-Werror`。modpost.c 是 host 工具，**没有** `__maybe_unused`，但文件里本就用过 `__attribute__((unused))` |
| `____version_ext_names[] ... =` 后补 `""` | `check_exports` 不跑 → `s->module` 恒 NULL → `add_extended_versions()` 一条名字都不发 → 生成 `=\n;`，空的字符串初始化器不合法（空的 `{}` 反而合法，所以只有 names 炸）。开 `CONFIG_RUST` 会带出 `CONFIG_EXTENDED_MODVERSIONS` 才走到这条路径 |

`setup_source_prebuilt` 也要调 `patch_modpost`：老的 src tarball 是用旧补丁打的，
只有前两条。四条 sed 都是幂等的，重复跑无害。

---

## 步骤 4：CNB 服务器上跑真东西

服务器是基于 `ddk-prebuilts` 开的 64 核 CNB 开发机，`/workspace` 就是 ddk-prebuilts
的工作副本（LFS 已实体化）。**地址每次重建都会变，用之前先问用户。**
服务器上是 root、**没有 sudo**，`/opt/ddk` 已存在（镜像预置了一份旧 clang/rust）。

> 环境重建 = `/opt/ddk`、`/ddk`、`/workspace` 全部回到初始状态，**没提交的产物全丢**。
> 长任务开始前先跟用户确认环境不会被回收，或者做完尽快提交。

```bash
SRV=<cnb-xxx@cnb.space>
ssh $SRV "echo OK; nproc; df -h /workspace /"
```

### 4.1 准备 /ddk

```bash
ssh $SRV '
set -e
rm -rf /ddk
GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 https://cnb.cool/Ylarod/ddk /ddk
cd /ddk
rm -rf prebuilts && ln -sfn /workspace /ddk/prebuilts   # pack.sh 直接写进 ddk-prebuilts
'
```

本地改动还没提交时用 `scp` 送上去，不要为了跑构建抢先 push。

### 4.2 下载工具链 + 源码

已有版本用 `-s prebuilt`（直接解 `/workspace` 里的 tar.zst，秒级），
新版本用 `-s download`（clang ≈1.08 GB、rust ≈0.99 GB 的 tar.gz，googlesource 现打包，
3–5 MB/s，约 10 分钟）。

**所有长任务都用 `setsid nohup ... & disown` + 日志轮询**，前台跑会被 SSH 超时打断：

```bash
ssh $SRV "cd /opt/ddk; setsid nohup bash -c '
  cd /opt/ddk
  CNB=true python3 /ddk/build/build-ddk.py setup-toolchain --android $NEW -s download &&
  CNB=true python3 /ddk/build/build-ddk.py setup-src       --android $NEW -s download
  echo SETUP_EXIT=\$?' > /tmp/ddk-setup.log 2>&1 < /dev/null & disown"

ssh $SRV 'grep -a "SETUP_EXIT\|saved\|Cloning\|bindgen\|fatal" /tmp/ddk-setup.log | tail'
```

下载完核一遍：

```bash
ssh $SRV '
grep -n "check_exports\|version_ext_names\\\\\") =" /opt/ddk/src/'$NEW'/scripts/mod/modpost.c
/opt/ddk/clang/clang-r584948c/bin/clang --version | head -1
/opt/ddk/rust/rust-1.91.1.p3/bin/rustc --version
/opt/ddk/rust/rust-1.91.1.p3/bin/bindgen --version'
```

再花 1 分钟确认 `CONFIG_RUST` 真能开起来（比编 15 分钟再发现强）：

```bash
ssh $SRV 'export CROSS_COMPILE=aarch64-linux-gnu- ARCH=arm64 LLVM=1 LLVM_IAS=1
PATH=/opt/ddk/clang/clang-r584948c/bin:/opt/ddk/rust/rust-1.91.1.p3/bin:$PATH \
  make -C /opt/ddk/src/'$NEW' O=/tmp/cfgprobe gki_defconfig > /dev/null 2>&1
grep -E "^CONFIG_RUST=|^# CONFIG_RUST is not set" /tmp/cfgprobe/.config'
```

### 4.3 编译内核（先全量，再精简）

**顺序不能反** —— `--min` 会把 `kdir/<ver>` 挪成 `kdir-full/<ver>`，之后就打不出全量包了。
`--min` 是**逐版本**搬的，所以对第二个版本再跑不会毁掉第一个版本的 kdir-full。

```bash
# ① 全量 kdir（64 核约 15 分钟）
CNB=true python3 /ddk/build/build-ddk.py build --android $NEW -j64
# ② 打全量包（必须在 ③ 之前）
/ddk/build/pack.sh -k -v $NEW
# ③ 精简 kdir：modules_prepare + 从 kdir-full 补头文件和构建文件
CNB=true python3 /ddk/build/build-ddk.py build --android $NEW --min -j64
# ④ 打精简包
/ddk/build/pack.sh -m -v $NEW
```

编译失败要重来时 `build` 会因为 kdir 已存在直接 skip，用 `rebuild`（自带清理）或先
`rm -rf /opt/ddk/kdir/$NEW`。整轮重来则 `rm -rf /opt/ddk/kdir /opt/ddk/kdir-full`。

手动复现构建（排错时用）：

```bash
export PATH=/opt/ddk/clang/clang-r584948c/bin:/opt/ddk/rust/rust-1.91.1.p3/bin:$PATH
export LIBCLANG_PATH=/opt/ddk/clang/clang-r584948c/lib
export CROSS_COMPILE=aarch64-linux-gnu- ARCH=arm64 LLVM=1 LLVM_IAS=1
SRC=/opt/ddk/src/$NEW; OUT=/opt/ddk/kdir/$NEW
cd $SRC
make O=$OUT gki_defconfig
$SRC/scripts/config --file $OUT/.config -e CONFIG_CFI_ICALL_NORMALIZE_INTEGERS
make O=$OUT -j64
```

### 4.4 打包到 /workspace

`pack.sh` 输出到 `<repo>/prebuilts/<类别>/`，因为 4.1 的软链实际落在 `/workspace/`：

```bash
/ddk/build/pack.sh -c -v clang-r584948c   # -> /workspace/clang/clang-r584948c.tar.zst
/ddk/build/pack.sh -r -v rust-1.91.1.p3   # -> /workspace/rust/rust-1.91.1.p3.tar.zst
/ddk/build/pack.sh -s -v $NEW             # -> /workspace/src/src.$NEW.tar.zst
```

android17-6.18 的参考大小：

| 路径 | 大小 |
|---|---|
| `clang/clang-r584948c.tar.zst` | 857 MB |
| `rust/rust-1.91.1.p3.tar.zst` | 857 MB |
| `src/src.$NEW.tar.zst` | 192 MB |
| `kdir/kdir.$NEW.tar.zst` | 1.29 GB |
| `kdir-min/kdir.$NEW.tar.zst` | 226 MB |

注意 kdir-min 里的文件名是 `kdir.<ver>.tar.zst`（**不是** `kdir-min.<ver>`），
`docker/ddk-min/Dockerfile` 就是按这个名字挂载的。

### 4.5 冒烟测试

打包完验一下 kdir 真能编外部模块：

```bash
rm -rf /tmp/tm && mkdir -p /tmp/tm && cd /tmp/tm
cat > hello.c <<'EOF'
#include <linux/module.h>
static int __init m_init(void) { return 0; }
static void __exit m_exit(void) {}
module_init(m_init);
module_exit(m_exit);
MODULE_LICENSE("GPL");
EOF
echo "obj-m += hello.o" > Makefile
export PATH=/opt/ddk/clang/clang-r584948c/bin:/opt/ddk/rust/rust-1.91.1.p3/bin:$PATH
export LIBCLANG_PATH=/opt/ddk/clang/clang-r584948c/lib
make -C /opt/ddk/kdir/$NEW M=/tmp/tm ARCH=arm64 LLVM=1 LLVM_IAS=1 \
     CROSS_COMPILE=aarch64-linux-gnu- modules
file /tmp/tm/hello.ko    # 应为 ELF 64-bit LSB relocatable, ARM aarch64
```

### 4.6 提交 prebuilts（**先问用户**）

push 是对外动作，明确得到同意再做：

```bash
ssh $SRV "cd /workspace && git add -A && git status --short &&
          git commit -m 'add $NEW prebuilts' && git push"
```

推完在本地更新子模块指针（**记得 GIT_LFS_SKIP_SMUDGE=1**）：

```bash
GIT_LFS_SKIP_SMUDGE=1 git -C prebuilts pull
git add prebuilts
```

---

## 步骤 5：构建镜像

镜像同样由 matrix 驱动，改完 mapping.json 就自动带上新版本。
**镜像在另一台机器上建**——构建机是 64 核跑编译的，镜像机只要 8 核，
但要能拉 LFS 和推 registry。**地址同样每次重建都变，先问用户。**

镜像层级（都硬编码 `docker.cnb.cool/ylarod/ddk` 作为 base，所以 `REG` 保持默认）：

```
ddk-builder:latest                    基础环境（apt 那堆）
  └─ ddk-toolchain:<ver>              解 clang + rust(含 bindgen) tar.zst
       ├─ ddk:<ver>                   + src + kdir（全量）
       └─ ddk-min:<ver>               + src + kdir-min
ddk-cnb-dev:latest                    FROM ddk-builder，给 CNB 开发机用
```

### 5.1 准备镜像机

这台的 `/workspace` 是 **ddk 仓库本身**（不是 ddk-prebuilts），和步骤 4 那台不一样。

```bash
IMG_SRV=<cnb-xxx@cnb.space>
ssh $IMG_SRV 'nproc; free -g | head -2; df -h /; docker buildx ls | head -3'
```

精简镜像里**没有 make/jq**，先装（`.cnb.yml` 里那条 apt 就是干这个的）：

```bash
ssh $IMG_SRV 'apt-get update -qq && apt-get install -y -qq --no-install-recommends make jq'
```

registry 凭据 CNB 已经写好在 `~/.docker/config.json`（`docker.cnb.cool`），不用登录。

拉代码 + submodule，**submodule 先 skip LFS，再按需单独拉**（全量 LFS 十几 GB，
只建两个版本的话没必要）：

```bash
ssh $IMG_SRV 'cd /workspace
git pull --ff-only
GIT_LFS_SKIP_SMUDGE=1 git submodule update --init --depth 1 prebuilts
cd prebuilts && git lfs pull --include="\
clang/clang-r536225.tar.zst,clang/clang-r584948c.tar.zst,\
rust/rust-1.82.0.tar.zst,rust/rust-1.91.1.p3.tar.zst,\
src/src.android16-6.12.tar.zst,src/src.android17-6.18.tar.zst,\
kdir/kdir.android16-6.12.tar.zst,kdir/kdir.android17-6.18.tar.zst,\
kdir-min/kdir.android16-6.12.tar.zst,kdir-min/kdir.android17-6.18.tar.zst"'
```

每个版本需要 5 个文件：`clang` / `rust` / `src` / `kdir` / `kdir-min`。
拉完确认它们是实体文件（几百 MB～1 GB），没拉的仍是 134 字节指针。

### 5.2 只建改动过的版本

`make toolchains` 会遍历**整个 matrix**（8 个版本）。命令行覆盖 `MATRIX` 限定范围
（make 的命令行赋值优先级高于 makefile 里的 `:=`）：

```bash
ssh $IMG_SRV 'cd /workspace
M="android16-6.12:clang-r536225:rust-1.82.0 android17-6.18:clang-r584948c:rust-1.91.1.p3"
make -C docker list MATRIX="$M"        # 先确认覆盖生效，只列出这两个
make -C docker toolchains PUSH=1 MATRIX="$M"'
```

`build` / `build-min` 有单版本入口，不用覆盖 MATRIX：

```bash
for V in android16-6.12 android17-6.18; do
  make -C docker build     VER=$V PUSH=1
  make -C docker build-min VER=$V PUSH=1
done
```

**顺序不能反**：`ddk` 和 `ddk-min` 都 `FROM ddk-toolchain:<ver>`，toolchain 必须先推上去。

`PUSH=1` 走 `buildx --push`，不落本地，所以 `toolchains` 里那个
"镜像已存在就跳过" 的判断永远不成立，每次都会重建。

单个镜像 export+push 约 3 分钟（ddk 解压后 ~15 GB），四个镜像 15–20 分钟。
轮询：

```bash
ssh $IMG_SRV 'grep -a "==> Building\|ERROR" /tmp/img-all.log | tail
              grep -a -c "pushing manifest for" /tmp/img-all.log'
```

### 5.3 验镜像

```bash
for t in ddk-toolchain ddk ddk-min; do
  for v in android16-6.12 android17-6.18; do
    printf "%-34s " "$t:$v"
    docker manifest inspect docker.cnb.cool/ylarod/ddk/$t:$v >/dev/null 2>&1 && echo OK || echo MISSING
  done
done
```

再从 registry 拉一个下来真编一次。**CNB 的 docker 是独立服务，`-v` 挂的是 daemon
那边的路径，宿主机上写的文件容器里看不到**，所以源码要在容器内生成：

```bash
docker run --rm docker.cnb.cool/ylarod/ddk/ddk-min:android17-6.18 bash -c '
set -e
mkdir -p /tmp/tm && cd /tmp/tm
cat > hello.c <<EOF
#include <linux/module.h>
static int __init m_init(void) { return 0; }
static void __exit m_exit(void) {}
module_init(m_init);
module_exit(m_exit);
MODULE_LICENSE("GPL");
EOF
echo "obj-m += hello.o" > Makefile
bindgen --version; rustc --version
make -C "$KDIR" M=/tmp/tm modules
file /tmp/tm/hello.ko'
```

镜像里 `ARCH` / `LLVM` / `CROSS_COMPILE` / `KDIR` / `LIBCLANG_PATH` 都是 ENV，
不用再传。结果应为 `ELF 64-bit LSB relocatable, ARM aarch64`。

### 5.4 全量重建

要重建所有版本时用仓库根目录的 `build.sh`（`build-min-all` → `build-all` → `cnb-dev`）。
注意它**不含 `toolchains`**，新版本的 toolchain 镜像得先单独建。
`ddk-cnb-dev` 需要 `prebuilts/clang/` 和 `prebuilts/rust/` 的全部 LFS 文件。

CNB 上也可以走 `.cnb.yml` 的 web_trigger 按钮，不用手跑。

---

## 步骤 6：日期 tag + 同步到 GHCR / Docker Hub

### 6.1 给 CNB 镜像打日期 tag

`DATE` 用 `date +%Y%m%d`（如 `20260828`）。这是**整套镜像的快照标记**，
所以三个仓库（`ddk` / `ddk-min` / `ddk-toolchain`）× mapping.json 里**全部** android
版本都要打，不只是这次改动的那两个 —— 少几个的话快照就不完整了。

`build/tag-image.sh` 是按 `docker image ls` 找**本地**镜像的，而步骤 5 用 `PUSH=1`
（`buildx --push`）根本不落本地，所以那个脚本在这条路径上找不到东西。
直接用 `imagetools create` 在 registry 侧改名，不拉不推任何层：

```bash
ssh $IMG_SRV 'cd /workspace
DATE=20260828
for repo in ddk ddk-min ddk-toolchain; do
  jq -r ".android[].name" mapping.json | while IFS= read -r v; do
    SRC="docker.cnb.cool/ylarod/ddk/$repo:$v"
    DST="docker.cnb.cool/ylarod/ddk/$repo:$v-$DATE"
    docker buildx imagetools create --tag "$DST" "$SRC" \
      && echo "OK    $repo:$v-$DATE" || echo "FAIL  $repo:$v-$DATE"
  done
done'
```

打之前先确认源 tag 都在：

```bash
docker buildx imagetools inspect docker.cnb.cool/ylarod/ddk/$repo:$v >/dev/null 2>&1
```

> CNB 开发机的 shell 是 **zsh**，`for v in $VERS` 不做分词，会把整段当成一个元素
> （表现为只处理第一个、后面全被 echo 出来）。遍历一律用
> `jq ... | while IFS= read -r v`，别用 `for ... in $VAR`。

### 6.2 推 git

镜像 tag 打完再推 git，github 和 cnb 两个 remote 都要推。

### 6.3 跑 GitHub 的 sync workflow

`.github/workflows/sync-image.yml` 是 `workflow_dispatch`，有一个可选的 `date` 输入：

```bash
gh workflow run sync-image.yml -f date=20260828
gh run watch "$(gh run list --workflow=sync-image.yml -L1 --json databaseId -q '.[0].databaseId')"
```

它做两件事，链路是 **CNB → GHCR → Docker Hub**：

1. `sync-toolchain`：`ddk-toolchain:<ver>`，矩阵取自 `mapping.json` 的 `.matrix`
2. `sync-image`：`ddk:<ver>` 和 `ddk-min:<ver>`，矩阵取自 `.android`，依赖上一步

填了 `date` 的话每个 tag 同步两遍：一次不带日期，一次 `--new-date`。
注意 `--new-date` 的语义是 **`src:ver -> dst:ver-<date>`** —— 读的是**不带日期**的源 tag，
在目标端写出带日期的 tag。所以 CI **不依赖** CNB 上有日期 tag，
6.1 那步是给 CNB 自己留快照，两件事互相独立。

矩阵直接来自 mapping.json，新版本加进去就自动带上，workflow 本身不用改。

---

## 检查清单

- [ ] `mapping.json` 四处（clang / rust / android / matrix）都加了，JSON 合法
- [ ] rust 版本带 `.pN` 后缀
- [ ] `CFI_NORMALIZE_INTEGERS_BRANCHES` 加了新版本
- [ ] 服务器上 `/ddk/prebuilts -> /workspace` 软链存在
- [ ] `bindgen --version` 能跑，`gki_defconfig` 出来是 `CONFIG_RUST=y`
- [ ] `.config` 里 `CONFIG_CFI_ICALL_NORMALIZE_INTEGERS=y`
- [ ] 打包顺序：`build` → `pack -k` → `build --min` → `pack -m`
- [ ] 五个 tarball 齐全、`kdir-min` 里叫 `kdir.<ver>.tar.zst`
- [ ] 冒烟测试编出 aarch64 `.ko`
- [ ] 本地全程 `GIT_LFS_SKIP_SMUDGE=1`
- [ ] 镜像机上 `make`/`jq` 装了，submodule 按需拉 LFS
- [ ] `toolchains` 先于 `build`/`build-min`，且用 MATRIX 覆盖限定版本
- [ ] 六个镜像 `docker manifest inspect` 都 OK，拉下来能真编出 `.ko`
- [ ] CNB 上三个仓库 × 全部版本都打了 `-<date>` tag
- [ ] git 推了 github + cnb，`sync-image.yml` 带 `date` 跑通

## 坑

- **bindgen 不在 rust 包里**：AOSP 的 rust 预编译 `bin/` 只有 rustc/cargo，没有 bindgen；
  内核 `scripts/rust_is_available.sh` 找不到它就**静默**关掉 `CONFIG_RUST`，
  `.config` 里只剩 `CONFIG_RUSTC_*` 探测结果，很容易没发现。
  `ensure_bindgen()` 从 `platform/prebuilts/clang-tools` 的 `linux-x86/bin/bindgen`
  单独拉一个文件塞进 `/opt/ddk/rust/<ver>/bin/`（那目录已在 PATH 上，`pack.sh -r`
  也会一起打包）。它是自包含的（不依赖 clang-tools 的 `lib64/`），完整
  `linux-x86` 要 364 MB 而只 bindgen 是 20 MB，没必要拉全。
  版本跟着 manifest 分支走：main-kernel-2025 → 0.69.5，main-kernel-2026 → 0.72.1。
- **必须设 `LIBCLANG_PATH`**：bindgen 是 dlopen libclang 的，不指定就去 `/usr/lib*`
  摸系统那份。系统 libclang 比内核用的 clang 旧时会报
  `unknown warning option '-Wno-default-const-init-unsafe'`（内核 CFLAGS 里有新 clang
  才认识的 `-W` 选项），而且构建不封闭。指向 `/opt/ddk/clang/<ver>/lib`。
  `_make_kernel_env()` 和三个 Dockerfile 都设了。
- **modpost 的两个连锁问题**：见步骤 3.2 的表。换新 clang 看 `-Werror`，开 Rust 看
  `____version_ext_names`。
- **`--min` 的破坏性**：它把 `kdir/<ver>` 搬去 `kdir-full/<ver>`，全量包必须在它之前打。
  （已改成逐版本搬，多版本轮流跑 `--min` 是安全的；整目录 rename 的老写法会毁掉
  上一个版本的 kdir-full。）
- **`pack.sh` 的 `-m`**：输出目录名和文件名前缀是两个参数（`pack_dir` 的 `$1` 是文件名
  前缀、`$4` 是输出目录），别再合成一个，否则会打出 `kdir-min.<ver>.tar.zst`。
  另外 kdir 的 tar mtime 要比 src 晚 1 秒，靠 `prefix == "kdir"` 判断，合并参数也会破坏这点。
- **流水线重叠不生效**：`build_kernels()` 会在看到同时含 "LTO" 和 "vmlinux" 的行时提前
  启动下一个构建，但不传 `--lto` 时 `gki_defconfig` 出来是 `CONFIG_LTO_NONE=y`，
  日志里 "LTO" 出现 0 次，触发条件永远不命中，实际是串行。要重叠得传 `--lto thin/full`
  （会改变 kdir 配置，和现有版本不一致）。LTO_NONE 下 `-j64` 已经吃满并行，收益不大。
- **镜像机是另一台**：`/workspace` 在那边是 **ddk 仓库本身**，不是 ddk-prebuilts；
  而且是精简镜像，**没装 make/jq**。`make toolchains` 没有单版本入口，
  要靠命令行覆盖 `MATRIX` 限定范围。
- **CNB 的 docker 是独立服务**：`docker run -v /host/path:/x` 挂的是 daemon 那边的
  路径，宿主机上刚写的文件在容器里是空的。验镜像时源码要在容器内生成。
- **本地 LFS**：忘了 `GIT_LFS_SKIP_SMUDGE=1` 会拖十几 GB 下来。
- **SSH 断连**：CNB 开发机重建后地址会变，出现 `Received disconnect ... 22:11`
  就是环境没了，向用户要新地址，别反复重试。

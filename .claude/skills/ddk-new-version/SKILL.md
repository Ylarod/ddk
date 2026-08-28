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

## 步骤 5：镜像

镜像同样由 matrix 驱动，改完 mapping.json 就自动带上新版本：

```bash
make -C docker toolchains PUSH=1 REG=<registry>   # ddk-toolchain:$NEW（clang+rust+bindgen）
make -C docker build      VER=$NEW PUSH=1
make -C docker build-min  VER=$NEW PUSH=1
```

在 CNB 上通常走 `.cnb.yml` 的 web_trigger 按钮，不用手跑。

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
- **本地 LFS**：忘了 `GIT_LFS_SKIP_SMUDGE=1` 会拖十几 GB 下来。
- **SSH 断连**：CNB 开发机重建后地址会变，出现 `Received disconnect ... 22:11`
  就是环境没了，向用户要新地址，别反复重试。

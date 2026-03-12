#!/usr/bin/env python3

import argparse
import json
import os
import shutil
import subprocess
import sys
import threading
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
DDK_ROOT = Path("/opt/ddk")
DEFAULT_MAP_FILE = PROJECT_ROOT / "mapping.json"
PREBUILTS_DIR = PROJECT_ROOT / "prebuilts"


def run(cmd, cwd=None, env=None):
    print(f"  > {cmd}")
    result = subprocess.run(cmd, shell=True, cwd=cwd, env=env)
    if result.returncode != 0:
        print(f"[x] 命令失败 (exit {result.returncode}): {cmd}")
        sys.exit(result.returncode)


def load_mapping(map_file):
    if not map_file.is_file():
        print(f"[x] 未找到 mapping.json: {map_file}")
        sys.exit(2)
    with open(map_file) as f:
        return json.load(f)


def ensure_ddk_root():
    """确保 /opt/ddk 目录存在并归当前用户所有"""
    if not DDK_ROOT.is_dir():
        print("[+] 创建 /opt/ddk ...")
        run(f"sudo mkdir -p {DDK_ROOT}")
    # 检查所有权
    import getpass, grp
    user = getpass.getuser()
    gid = os.getgid()
    group = grp.getgrgid(gid).gr_name
    stat = DDK_ROOT.stat()
    if stat.st_uid != os.getuid() or stat.st_gid != gid:
        print(f"[+] 修改 {DDK_ROOT} 所有者为 {user}:{group}")
        run(f"sudo chown -R {user}:{group} {DDK_ROOT}")


def extract_prebuilt(component, name, base_dir, prefix=""):
    """从 prebuilts 解压 tar.zst 到目标目录"""
    tarball = PREBUILTS_DIR / component / f"{prefix}{name}.tar.zst"
    if not tarball.is_file():
        print(f"[x] 预构建包不存在: {tarball}")
        sys.exit(1)
    dest = base_dir / name
    if dest.is_dir():
        print(f"[!] {name} already exists, skip")
        return
    base_dir.mkdir(parents=True, exist_ok=True)
    print(f"[+] 解压 {tarball.name} -> {dest}")
    run(f"tar -xf {tarball} -C {base_dir}")


# ── clang ──────────────────────────────────────────────

def setup_clang_download(branch, version):
    dest = DDK_ROOT / "clang" / version
    if dest.is_dir():
        print(f"[!] {version} already exists, skip")
        return
    url = f"https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/{branch}/{version}.tar.gz"
    print(f"[+] Download from {url}")
    tarball = f"{version}.tar.gz"
    run(f"wget {url} -O {tarball}")
    dest.mkdir(parents=True, exist_ok=True)
    run(f"tar xzf {tarball} -C {dest}")
    os.remove(tarball)


def setup_clang_prebuilt(version):
    extract_prebuilt("clang", version, DDK_ROOT / "clang")


# ── rust ───────────────────────────────────────────────

def setup_rust_download(version, branch, repo):
    ver_num = version.removeprefix("rust-")
    dest = DDK_ROOT / "rust" / version
    if dest.is_dir():
        print(f"[!] {version} already exists, skip")
        return
    # platform/prebuilts/rust (旧仓库) 需要额外拼 linux-x86 子路径
    if repo == "platform/prebuilts/rust":
        archive_path = f"linux-x86/{ver_num}"
    else:
        archive_path = ver_num
    url = f"https://android.googlesource.com/{repo}/+archive/refs/heads/{branch}/{archive_path}.tar.gz"
    print(f"[+] Download from {url}")
    tarball = f"{version}.tar.gz"
    run(f"wget {url} -O {tarball}")
    dest.mkdir(parents=True, exist_ok=True)
    run(f"tar xzf {tarball} -C {dest}")
    os.remove(tarball)


def setup_rust_prebuilt(version):
    extract_prebuilt("rust", version, DDK_ROOT / "rust")


# ── src ────────────────────────────────────────────────

def setup_source_download(name, branch=None):
    if not branch:
        branch = name
    dest = DDK_ROOT / "src" / name
    if dest.is_dir():
        print(f"[!] {name} already exists, skip")
        return
    print(f"[+] Clone {name} (branch: {branch})")
    run(f"git clone https://android.googlesource.com/kernel/common -b {branch} --depth 1 {dest}")
    modpost = dest / "scripts" / "mod" / "modpost.c"
    if modpost.is_file():
        run(f"sed -i 's/^\\(\\s*check_exports(mod);\\)/\\/\\/\\1/' {modpost}")
        run(f"sed -i 's/^\\(\\s*s->module = exp->module;\\)/\\/\\/\\1/' {modpost}")


def setup_source_prebuilt(name):
    extract_prebuilt("src", name, DDK_ROOT / "src", prefix="src.")


# ── build ──────────────────────────────────────────────

def _drain_output(proc, tag):
    """后台线程：持续消费进程剩余输出"""
    for line in proc.stdout:
        sys.stdout.write(f"[{tag}] {line}")
    sys.stdout.flush()


def _make_kernel_env(clang_version):
    """构造内核编译所需的环境变量"""
    clang_bin = (DDK_ROOT / "clang" / clang_version / "bin").resolve()
    env = os.environ.copy()
    env["PATH"] = f"{clang_bin}:{env['PATH']}"
    env["CROSS_COMPILE"] = "aarch64-linux-gnu-"
    env["ARCH"] = "arm64"
    env["LLVM"] = "1"
    env["LLVM_IAS"] = "1"
    return env


def _configure_kernel(src_path, out_path_abs, env, lto=None, android_branch=None):
    """defconfig + LTO 配置"""
    run(f"make O={out_path_abs} gki_defconfig", cwd=src_path, env=env)

    scripts_config = src_path / "scripts" / "config"
    config_file = out_path_abs / ".config"
    if lto == "none":
        run(f"{scripts_config} --file {config_file} -d LTO_CLANG -e LTO_NONE -d LTO_CLANG_THIN -d LTO_CLANG_FULL -d THINLTO", env=env)
    elif lto == "thin":
        run(f"{scripts_config} --file {config_file} -e LTO_CLANG -d LTO_NONE -e LTO_CLANG_THIN -d LTO_CLANG_FULL -e THINLTO", env=env)
    elif lto == "full":
        run(f"{scripts_config} --file {config_file} -e LTO_CLANG -d LTO_NONE -d LTO_CLANG_THIN -e LTO_CLANG_FULL -d THINLTO", env=env)

    if android_branch == "android16-6.12":
        run(f"{scripts_config} --file {config_file} -e CONFIG_CFI_ICALL_NORMALIZE_INTEGERS", env=env)


def build_kernel_start(clang_version, android_branch, lto=None, build_proc=None):
    """配置并启动内核编译，返回 (Popen, tag) 或 None（已跳过）"""
    out_path = DDK_ROOT / "kdir" / android_branch
    if out_path.is_dir():
        print(f"[!] {android_branch} already exists, skip")
        return None

    src_path = DDK_ROOT / "src" / android_branch
    if not src_path.is_dir():
        print(f"[x] 源码目录不存在: {src_path}")
        sys.exit(1)

    print(f"[+] Building {android_branch}")

    env = _make_kernel_env(clang_version)
    out_path_abs = out_path.resolve()
    out_path.mkdir(parents=True, exist_ok=True)
    _configure_kernel(src_path, out_path_abs, env, lto=lto, android_branch=android_branch)

    if build_proc is None:
        build_proc = os.cpu_count() or 1

    cmd = f"make O={out_path_abs} -j{build_proc}"
    print(f"  > {cmd}")
    proc = subprocess.Popen(
        cmd, shell=True, cwd=src_path, env=env,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, bufsize=1,
    )
    return proc, android_branch


def build_kernel_modules_prepare(clang_version, android_branch, lto=None, build_proc=None):
    """仅执行 modules_prepare（生成精简 kdir）"""
    out_path = DDK_ROOT / "kdir" / android_branch
    if out_path.is_dir():
        print(f"[!] {android_branch} already exists, skip modules_prepare")
        return

    src_path = DDK_ROOT / "src" / android_branch
    if not src_path.is_dir():
        print(f"[x] 源码目录不存在: {src_path}")
        sys.exit(1)

    print(f"[+] modules_prepare {android_branch}")

    env = _make_kernel_env(clang_version)
    out_path_abs = out_path.resolve()
    out_path.mkdir(parents=True, exist_ok=True)
    _configure_kernel(src_path, out_path_abs, env, lto=lto, android_branch=android_branch)

    if build_proc is None:
        build_proc = os.cpu_count() or 1

    run(f"make O={out_path_abs} modules_prepare", cwd=src_path, env=env)


HEADER_SUFFIXES = {".h", ".hpp", ".hxx", ".h++", ".hh"}

# 构建外部内核模块所需的顶层文件
BUILD_FILES = [
    "Module.symvers",
    "vmlinux",
    "vmlinux.symvers",
    "System.map",
    "modules.order",
    "modules.builtin",
    "modules.builtin.modinfo",
]


def fix_kdir_min(kdir_full: Path, kdir_min: Path):
    """从完整构建目录拷贝缺失的头文件和构建文件到精简目录"""
    for kernel_full in sorted(kdir_full.iterdir()):
        if not kernel_full.is_dir():
            continue
        kernel_min = kdir_min / kernel_full.name
        if not kernel_min.is_dir():
            continue

        print(f"[+] 修补 kdir-min: {kernel_full.name}")

        # 拷贝构建文件
        for name in BUILD_FILES:
            src_file = kernel_full / name
            dst_file = kernel_min / name
            if not src_file.is_file() or dst_file.exists():
                continue
            shutil.copy2(src_file, dst_file)
            print(f"  复制构建文件: {name}")

        # 拷贝缺失的头文件
        header_copied = 0
        for src_file in kernel_full.rglob("*"):
            if not src_file.is_file():
                continue
            if src_file.suffix.lower() not in HEADER_SUFFIXES:
                continue
            rel = src_file.relative_to(kernel_full)
            dst_file = kernel_min / rel
            if dst_file.exists():
                continue
            dst_file.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src_file, dst_file)
            header_copied += 1
        print(f"  复制 {header_copied} 个头文件")


def build_kernels(matrix_list, lto=None, build_proc=None):
    """流水线编译多个内核：检测到 LTO vmlinux 后立即启动下一个"""
    background_procs = []  # (proc, tag, thread)

    for i, item in enumerate(matrix_list):
        clang_ver = item.get("clang")
        android_ver = item.get("android")
        if not clang_ver or not android_ver:
            continue

        result = build_kernel_start(clang_ver, android_ver, lto=lto, build_proc=build_proc)
        if result is None:
            continue

        proc, tag = result
        is_last = (i == len(matrix_list) - 1)

        if is_last:
            # 最后一个：直接等待完成
            for line in proc.stdout:
                sys.stdout.write(f"[{tag}] {line}")
            sys.stdout.flush()
            proc.wait()
            if proc.returncode != 0:
                print(f"[x] {tag} 编译失败 (exit {proc.returncode})")
                sys.exit(proc.returncode)
        else:
            # 非最后一个：监控输出，检测到 LTO vmlinux 后启动下一个
            triggered = False
            for line in proc.stdout:
                sys.stdout.write(f"[{tag}] {line}")
                if not triggered and "LTO" in line and "vmlinux" in line:
                    print(f"[+] {tag} 已进入 LTO vmlinux 阶段，启动下一个构建")
                    triggered = True
                    break
            # 将剩余输出交给后台线程消费
            t = threading.Thread(target=_drain_output, args=(proc, tag), daemon=True)
            t.start()
            background_procs.append((proc, tag, t))

    # 等待所有后台构建完成
    failed = []
    for proc, tag, t in background_procs:
        t.join()
        proc.wait()
        if proc.returncode != 0:
            failed.append(tag)
            print(f"[x] {tag} 编译失败 (exit {proc.returncode})")

    if failed:
        print(f"[x] 以下构建失败: {', '.join(failed)}")
        sys.exit(1)


# ── 子命令 ─────────────────────────────────────────────

def filter_toolchains(mapping, android_ver):
    """通过 matrix 反查指定 android 版本需要的 clang 和 rust 版本"""
    clang_versions = set()
    rust_versions = set()
    for m in mapping.get("matrix", []):
        if m.get("android") == android_ver:
            if m.get("clang"):
                clang_versions.add(m["clang"])
            if m.get("rust"):
                rust_versions.add(m["rust"])
    if not clang_versions:
        print(f"[x] matrix 中未找到 android 版本: {android_ver}")
        sys.exit(1)
    clang_list = [c for c in mapping.get("clang", []) if c["version"] in clang_versions]
    rust_list = [r for r in mapping.get("rust", []) if r["version"] in rust_versions]
    return clang_list, rust_list


def cmd_setup_toolchain(args):
    mapping = load_mapping(args.map_file)
    ensure_ddk_root()
    if args.android:
        clang_list, rust_list = filter_toolchains(mapping, args.android)
    else:
        clang_list = mapping.get("clang", [])
        rust_list = mapping.get("rust", [])
    print("[+] Setup clang")
    for item in clang_list:
        if args.source == "prebuilt":
            setup_clang_prebuilt(item["version"])
        else:
            setup_clang_download(item["branch"], item["version"])
    print("[+] Setup rust")
    for item in rust_list:
        if args.source == "prebuilt":
            setup_rust_prebuilt(item["version"])
        else:
            setup_rust_download(item["version"], item["branch"], item["repo"])


def cmd_setup_src(args):
    mapping = load_mapping(args.map_file)
    ensure_ddk_root()
    android_list = mapping.get("android", [])
    if args.android:
        android_list = [a for a in android_list if a["name"] == args.android]
        if not android_list:
            print(f"[x] android 列表中未找到: {args.android}")
            sys.exit(1)
    print("[+] Setup kernel source")
    for item in android_list:
        if args.source == "prebuilt":
            setup_source_prebuilt(item["name"])
        else:
            setup_source_download(item["name"], item.get("branch"))


def cmd_build(args):
    """编译内核"""
    mapping = load_mapping(args.map_file)

    matrix_list = mapping.get("matrix", [])
    if args.android:
        matrix_list = [m for m in matrix_list if m.get("android") == args.android]

    print("[+] Build kernel")
    build_kernels(matrix_list, lto=args.lto, build_proc=args.jobs)

    if args.min:
        kdir = DDK_ROOT / "kdir"
        kdir_full = DDK_ROOT / "kdir-full"

        # mv kdir -> kdir-full
        if kdir.is_dir():
            if kdir_full.is_dir():
                shutil.rmtree(kdir_full)
            print(f"[+] mv {kdir} -> {kdir_full}")
            kdir.rename(kdir_full)

        # 构建 modules_prepare -> kdir（精简版）
        for item in matrix_list:
            clang_ver = item.get("clang")
            android_ver = item.get("android")
            if clang_ver and android_ver:
                build_kernel_modules_prepare(clang_ver, android_ver,
                                             lto=args.lto, build_proc=args.jobs)

        # 从 kdir-full 修补 kdir
        fix_kdir_min(kdir_full, kdir)


def cmd_rebuild(args):
    if not DDK_ROOT.is_dir():
        print("[x] /opt/ddk is not exist")
        sys.exit(1)

    mapping = load_mapping(args.map_file)

    kdir = DDK_ROOT / "kdir"
    if kdir.is_dir():
        if args.android:
            target = kdir / args.android
            if target.is_dir():
                print(f"[+] Removing {target}")
                shutil.rmtree(target)
        else:
            for p in kdir.glob("android*"):
                print(f"[+] Removing {p}")
                shutil.rmtree(p)

    matrix_list = mapping.get("matrix", [])
    if args.android:
        matrix_list = [m for m in matrix_list if m.get("android") == args.android]

    print("[+] Build kernel")
    build_kernels(matrix_list, lto=args.lto, build_proc=args.jobs)


def add_common_args(parser):
    parser.add_argument("--map-file", type=Path,
                        default=Path(os.environ.get("MAP_FILE", str(DEFAULT_MAP_FILE))),
                        help="mapping.json 路径")
    parser.add_argument("--lto", choices=["none", "thin", "full"],
                        default=os.environ.get("LTO"),
                        help="LTO 模式")
    parser.add_argument("-j", "--jobs", type=int,
                        default=int(os.environ.get("BUILD_PROC", 0)) or None,
                        help="并行编译线程数")


def add_source_arg(parser):
    parser.add_argument("-s", "--source", choices=["download", "prebuilt"],
                        default="download",
                        help="来源：download (网络下载) 或 prebuilt (本地 prebuilts 解压)")


def add_android_arg(parser):
    parser.add_argument("--android", type=str, default=None,
                        help="仅操作指定的 android 版本 (如 android16-6.12)")


def main():
    parser = argparse.ArgumentParser(description="DDK 构建工具")
    sub = parser.add_subparsers(dest="command", required=True)

    # build - 编译内核
    p_build = sub.add_parser("build", help="编译内核")
    add_common_args(p_build)
    add_android_arg(p_build)
    p_build.add_argument("--min", action="store_true",
                         help="同时构建 kdir-min（modules_prepare + 修补头文件和构建文件）")

    # setup-toolchain - clang + rust
    p_tc = sub.add_parser("setup-toolchain", help="安装工具链 (clang + rust)")
    add_common_args(p_tc)
    add_source_arg(p_tc)
    add_android_arg(p_tc)

    # setup-src - 仅源码
    p_src = sub.add_parser("setup-src", help="仅安装内核源码")
    add_common_args(p_src)
    add_source_arg(p_src)
    add_android_arg(p_src)

    # rebuild - 重新编译
    p_rebuild = sub.add_parser("rebuild", help="清理并重新编译所有内核")
    add_common_args(p_rebuild)
    add_android_arg(p_rebuild)

    args = parser.parse_args()

    commands = {
        "build": cmd_build,
        "setup-toolchain": cmd_setup_toolchain,
        "setup-src": cmd_setup_src,
        "rebuild": cmd_rebuild,
    }
    commands[args.command](args)


if __name__ == "__main__":
    main()

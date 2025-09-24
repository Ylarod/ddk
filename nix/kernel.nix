{ pkgs, lib }:

# Build a kernel tree for a given android common branch with a provided toolchain.
# Produces two outputs:
#  - kernel: the O= build directory (kdir/<ver> equivalent)
#  - source: the kernel source after applying the modpost patch

{ ver
, srcRev
, srcBranch
, toolchain
, lto ? null # one of null (default defconfig), "none", "thin", "full"
}:

let
  # Prefer vendored sources if present; otherwise fetch from AOSP.
  localSrcPath = ../src/${ver};
  srcDrv = if builtins.pathExists localSrcPath then
    pkgs.runCommand "${ver}-src-vendor" { preferLocalBuild = true; allowSubstitutes = false; } ''
      mkdir -p "$out"
      cp -a ${localSrcPath}/. "$out/"
    ''
  else
    pkgs.fetchgit {
      url = "https://android.googlesource.com/kernel/common";
      rev = srcRev;
      fetchSubmodules = false;
      leaveDotGit = false;
    };
in
pkgs.stdenv.mkDerivation {
  pname = "ddk-kernel-${ver}";
  version = srcRev;

  src = srcDrv;

  outputs = [ "out" "kernel" "source" ];

  nativeBuildInputs = [
    pkgs.bash
    pkgs.perl
    pkgs.bc
    pkgs.bison
    pkgs.flex
    pkgs.pkg-config
    pkgs.openssl
    pkgs.ncurses
  ];

  buildInputs = [
    pkgs.dwarves # provides pahole
  ];

  # Apply the modpost.c patch (comment out check_exports(mod);)
  postPatch = ''
    set -e
    if [ -f scripts/mod/modpost.c ]; then
      # make patching idempotent
      if grep -q "check_exports(mod);" scripts/mod/modpost.c; then
        substituteInPlace scripts/mod/modpost.c \
          --replace "check_exports(mod);" "//check_exports(mod);" || true
      fi
    fi
  '';

  buildPhase = ''
    set -euxo pipefail

    export PATH=${toolchain}/bin:$PATH
    export CROSS_COMPILE=aarch64-linux-gnu-
    export ARCH=arm64
    export LLVM=1
    export LLVM_IAS=1

    # Out-of-tree build dir
    OUT="$PWD/.out"
    mkdir -p "$OUT"

    make O="$OUT" gki_defconfig

    # Adjust LTO per request, matching envsetup.sh logic
    if [ "${lib.escapeShellArg (lto or "")}" = "none" ]; then
      scripts/config --file "$OUT/.config" \
        -d LTO_CLANG \
        -e LTO_NONE \
        -d LTO_CLANG_THIN \
        -d LTO_CLANG_FULL \
        -d THINLTO || true
    elif [ "${lib.escapeShellArg (lto or "")}" = "thin" ]; then
      scripts/config --file "$OUT/.config" \
        -e LTO_CLANG \
        -d LTO_NONE \
        -e LTO_CLANG_THIN \
        -d LTO_CLANG_FULL \
        -e THINLTO || true
    elif [ "${lib.escapeShellArg (lto or "")}" = "full" ]; then
      scripts/config --file "$OUT/.config" \
        -e LTO_CLANG \
        -d LTO_NONE \
        -d LTO_CLANG_THIN \
        -e LTO_CLANG_FULL \
        -d THINLTO || true
    fi

    make O="$OUT" -j"${toString (pkgs.stdenv.hostPlatform.parsed.cpu.cores or 4)}"
  '';

  installPhase = ''
    set -eux
    # Export build dir
    mkdir -p "$kernel"
    cp -a .out/. "$kernel/"
    # Export patched source tree
    mkdir -p "$source"
    cp -a . "$source/"
    # Keep $out minimal to satisfy multi-output rules
    mkdir -p "$out"
    printf '%s\n' "${ver}" > "$out/version"
  '';

  meta = with lib; {
    description = "DDK kernel build for ${ver} (AOSP common)";
    homepage = "https://android.googlesource.com/kernel/common";
    license = licenses.gpl2Only;
    platforms = [ "x86_64-linux" ];
  };
}


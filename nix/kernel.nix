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
  # Always fetch kernel sources from AOSP to avoid local workspace dependency.
  # Use builtins.fetchGit to avoid requiring a fixed-output hash.
  srcDrv = builtins.fetchGit {
    url = "https://android.googlesource.com/kernel/common";
    rev = srcRev;
    submodules = false;
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

    # Use an out-of-tree build directory to keep sources clean
    builddir="$(pwd)/.build"
    mkdir -p "$builddir"

    make O="$builddir" gki_defconfig
    make O="$builddir" modules_prepare -j"${toString (pkgs.stdenv.hostPlatform.parsed.cpu.cores or 4)}"
  '';

  installPhase = ''
    set -eux
    mkdir -p "$out" "$kernel" "$source"
    # kernel output: prepared build tree (O= directory)
    cp -a .build/. "$kernel/"
    # source output: patched source tree
    shopt -s dotglob
    cp -a --no-preserve=ownership --preserve=mode * "$source/"
    # minimal marker in $out
    printf '%s\n' "${ver}" > "$out/version"
  '';

  meta = with lib; {
    description = "DDK kernel build for ${ver} (AOSP common)";
    homepage = "https://android.googlesource.com/kernel/common";
    license = licenses.gpl2Only;
    platforms = [ "x86_64-linux" ];
  };
}

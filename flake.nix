{
  description = "DDK: Nix-based build + nix2container images";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix2container.url = "github:nlewo/nix2container";
    nix2container.flake = false; # treat as source tree to import lib
  };

  outputs = { self, nixpkgs, nix2container, ... }:
  let
    forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" ];
  in
  {
    packages = forAllSystems (system:
      let
        pkgs = import nixpkgs { inherit system; };
        lib = pkgs.lib;
        n2c = (import nix2container { inherit pkgs system; }).nix2container;

        versions = import ./nix/versions.nix { inherit lib; };

        # Inline: mkToolchain and mkKernel
        mkToolchain = { version }:
          let
            ws = builtins.getEnv "DDK_ROOT";
            workspace = if ws != "" then ws else throw "DDK_ROOT not set. export DDK_ROOT=<path to repo>";
            localDirPath = "${workspace}/clang/${version}";
          in if builtins.pathExists localDirPath then
            let
              src = builtins.path { path = localDirPath; name = "clang-${version}"; };
            in pkgs.linkFarm "${version}-vendor" [
              { name = "clang/${version}"; path = src; }
              { name = "bin"; path = src + "/bin"; }
            ]
          else
            throw "Missing local clang/${version}. Run: source ./envsetup.sh && setup_clang <branch> ${version}";

        mkKernel = { ver, srcRev, srcBranch, toolchain, lto ? null }:
          let
            ws = builtins.getEnv "DDK_ROOT";
            workspace = if ws != "" then ws else throw "DDK_ROOT not set. export DDK_ROOT=<path to repo>";
            pkgDir = "${workspace}/.pkg";
            srcTarPath = "${pkgDir}/src.${ver}.tar";
            kdirTarPath = "${pkgDir}/kdir.${ver}.tar";

            srcDirPath = "${workspace}/src/${ver}";
            kdirDirPath = "${workspace}/kdir/${ver}";

            haveSrcTar = builtins.pathExists srcTarPath;
            haveKdirTar = builtins.pathExists kdirTarPath;
            haveSrcDir = builtins.pathExists srcDirPath;
            haveKdirDir = builtins.pathExists kdirDirPath;

            srcTar = if haveSrcTar then builtins.path { path = srcTarPath; name = "src.${ver}.tar"; } else null;
            kdirTar = if haveKdirTar then builtins.path { path = kdirTarPath; name = "kdir.${ver}.tar"; } else null;
            srcDirStore = if haveSrcDir then builtins.path { path = srcDirPath; name = "src-${ver}"; } else null;
            kdirDirStore = if haveKdirDir then builtins.path { path = kdirDirPath; name = "kdir-${ver}"; } else null;

            script = if haveSrcTar && haveKdirTar then ''
                tar -xf ${srcTar}  -C "$source" --strip-components=1
                tar -xf ${kdirTar} -C "$kernel" --strip-components=1
              '' else if haveSrcDir && haveKdirDir then ''
                cp -a ${srcDirStore}/.  "$source/"
                cp -a ${kdirDirStore}/. "$kernel/"
              '' else ''
                echo "Missing prebuilt artifacts for ${ver}. Provide .pkg/src.${ver}.tar & kdir.${ver}.tar or ./src/${ver} & ./kdir/${ver}."
                exit 2
              '';
          in pkgs.runCommand "ddk-prebuilt-${ver}" {
            outputs = [ "out" "kernel" "source" ];
            nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnutar ];
          } ''
            set -eux
            mkdir -p "$source" "$kernel" "$out"
            ${script}
            printf '%s\n' "${ver}" > "$out/version"
          '';

        # Common base packages needed to build kernel modules (kept minimal)
        basePkgs = [
          pkgs.bashInteractive
          pkgs.coreutils
          pkgs.findutils
          pkgs.gnugrep
          pkgs.gawk
          pkgs.gnumake
          pkgs.gzip
          pkgs.xz
          pkgs.util-linux
          pkgs.pahole      # pahole
          pkgs.git
          pkgs.curl
          pkgs.jq
          pkgs.perl
          pkgs.bc
          pkgs.bison
          pkgs.flex
          pkgs.pkg-config
          pkgs.openssl
          pkgs.ncurses
          pkgs.gnutar
          pkgs.cacert        # CA bundle for TLS
        ];

        # Build a stable reusable base layer from Nix packages
        baseEnv = pkgs.buildEnv {
          name = "ddk-base-env";
          paths = basePkgs;
          ignoreCollisions = true;
          pathsToLink = [ "/bin" ];
        };
        baseLayer = n2c.buildLayer {
          copyToRoot = baseEnv;
        };

        baseImage = n2c.buildImage {
          name = "ghcr.io/ylarod/ddk-base";
          tag = "latest";
          layers = [ baseLayer ];
          config = {
            Env = [
              "DDK_ROOT=/opt/ddk"
              "PATH=${baseEnv}/bin:/usr/bin:/bin"
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              "NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
            Cmd = [ "bash" ];
            Labels = {
              "org.opencontainers.image.title" = "ddk-base";
              "org.opencontainers.image.description" = "DDK base image (nix-built, no apt)";
              "io.ddk.project" = "ddk";
              "io.ddk.variant" = "base";
            };
          };
        };

        # helper to build a DDK image for a given version key
        mkImage = ver:
          let
            spec = versions.${ver};
            tool = mkToolchain { version = spec.clang; };
            kdrv = mkKernel {
              ver = ver;
              srcRev = spec.srcRev;
              srcBranch = spec.srcBranch;
              toolchain = tool;
              # lto = null; # optionally set: "none" | "thin" | "full"
            };

            # Layer 1: toolchain only (reused across images sharing same clang)
            clangLayer = pkgs.linkFarm "ddk-clang-${spec.clang}" [
              { name = "opt/ddk/clang/${spec.clang}"; path = "${tool}/clang/${spec.clang}"; }
            ];
            clangContentLayer = n2c.buildLayer { copyToRoot = clangLayer; };

            # Layer 2: version-paired kdir + src (strongly bundled together)
            verLayer = pkgs.linkFarm "ddk-tree-${ver}" [
              { name = "opt/ddk/kdir/${ver}"; path = kdrv.kernel; }
              { name = "opt/ddk/src/${ver}"; path = kdrv.source; }
            ];
            verContentLayer = n2c.buildLayer { copyToRoot = verLayer; };
          in n2c.buildImage {
            name = "ghcr.io/ylarod/ddk";
            tag = ver;
            layers = [ baseLayer clangContentLayer verContentLayer ];
            copyToRoot = [ ];
            config = {
              Env = [
                "DDK_ROOT=/opt/ddk"
                "CROSS_COMPILE=aarch64-linux-gnu-"
                "ARCH=arm64"
                "LLVM=1"
                "LLVM_IAS=1"
                "KERNEL_SRC=/opt/ddk/kdir/${ver}"
                "CLANG_PATH=/opt/ddk/clang/${spec.clang}/bin"
                "PATH=/opt/ddk/clang/${spec.clang}/bin:${baseEnv}/bin:/usr/bin:/bin"
                "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
                "NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              ];
              Cmd = [ "bash" ];
              Labels = {
                "org.opencontainers.image.title" = "DDK ${ver}";
                "org.opencontainers.image.description" = "Kernel Driver Development Kit for ${ver} (nix-built, offline)";
                "io.ddk.project" = "ddk";
                "io.ddk.android.version" = ver;
                "io.ddk.clang.version" = spec.clang;
                "io.ddk.kernel.src" = ver;
              };
            };
          };

        # Produce ddk images keyed by version; also provide normalized keys for CLI-friendly attrs
        images = lib.mapAttrs (_: mkImage) versions;
        norm = ver: lib.replaceStrings [ "-" "." ] [ "_" "_" ] ver;
        ddkImages = lib.listToAttrs (map (ver: { name = norm ver; value = mkImage ver; }) (lib.attrNames versions));

        # Dev images: based on ddk (base + clang + src/kdir) plus Nix as package manager
        devTools = [ pkgs.nix pkgs.less pkgs.vim pkgs.python3Full pkgs.zip pkgs.unzip pkgs.wget ];
        devEnv = pkgs.buildEnv {
          name = "ddk-dev-env";
          paths = devTools;
          ignoreCollisions = true;
          pathsToLink = [ "/bin" ];
        };
        mkDevImage = ver:
          let
            spec = versions.${ver};
            tool = mkToolchain { version = spec.clang; };
            kdrv = mkKernel {
              ver = ver;
              srcRev = spec.srcRev;
              srcBranch = spec.srcBranch;
              toolchain = tool;
            };
            verLayer = pkgs.linkFarm "ddk-tree-${ver}" [
              { name = "opt/ddk/kdir/${ver}"; path = kdrv.kernel; }
              { name = "opt/ddk/src/${ver}"; path = kdrv.source; }
            ];
            clangLayer = pkgs.linkFarm "ddk-clang-${spec.clang}" [
              { name = "opt/ddk/clang/${spec.clang}"; path = "${tool}/clang/${spec.clang}"; }
            ];
            clangContentLayer = n2c.buildLayer { copyToRoot = clangLayer; };
            verContentLayer = n2c.buildLayer { copyToRoot = verLayer; };
            devContentLayer = n2c.buildLayer { copyToRoot = devEnv; };
          in n2c.buildImage {
            name = "ghcr.io/ylarod/ddk-dev";
            tag = ver;
            # Layered exactly as: ddk + dev tools
            layers = [ baseLayer clangContentLayer verContentLayer devContentLayer ];
            copyToRoot = [ ];
            initializeNixDatabase = true;
            config = {
              Env = [
                "DDK_ROOT=/opt/ddk"
                "CROSS_COMPILE=aarch64-linux-gnu-"
                "ARCH=arm64"
                "LLVM=1"
                "LLVM_IAS=1"
                "KERNEL_SRC=/opt/ddk/kdir/${ver}"
                "CLANG_PATH=/opt/ddk/clang/${spec.clang}/bin"
                "PATH=/opt/ddk/clang/${spec.clang}/bin:${baseEnv}/bin:${devEnv}/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin"
                "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
                "NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
                "NIX_CONFIG=experimental-features = nix-command flakes"
              ];
              Cmd = [ "bash" ];
              Labels = {
                "org.opencontainers.image.title" = "DDK Dev ${ver}";
                "org.opencontainers.image.description" = "Developer image with Nix package manager";
                "io.ddk.project" = "ddk";
                "io.ddk.android.version" = ver;
                "io.ddk.clang.version" = spec.clang;
                "io.ddk.variant" = "dev";
              };
            };
          };
        devImages = lib.mapAttrs (_: mkDevImage) versions;
        ddkDevImages = lib.listToAttrs (map (ver: { name = norm ver; value = mkDevImage ver; }) (lib.attrNames versions));
      in
      {
        ddk-base = baseImage;
        # friendly attribute paths: .#ddk.<normalized ver> and .#ddk-dev.<normalized ver>
        ddk = ddkImages;
        ddk-dev = ddkDevImages;
        # retain old direct keys for compatibility (require quotes due to dots)
      } // images // devImages
    );

    # Development shells
    devShells = forAllSystems (system:
      let
        pkgs = import nixpkgs { inherit system; };
        lib = pkgs.lib;
        # Reuse a subset of basePkgs used in images to ensure kernel build deps are present
        kernelDeps = [
          pkgs.bashInteractive pkgs.coreutils pkgs.findutils pkgs.gnugrep pkgs.gawk pkgs.gnumake
          pkgs.gzip pkgs.xz pkgs.util-linux pkgs.pahole pkgs.git pkgs.curl pkgs.jq pkgs.perl pkgs.bc
          pkgs.bison pkgs.flex pkgs.pkg-config pkgs.openssl pkgs.ncurses pkgs.gnutar pkgs.wget pkgs.zip pkgs.unzip
        ];
      in {
        default = pkgs.mkShell { packages = [ pkgs.git pkgs.curl pkgs.jq pkgs.coreutils pkgs.gnumake pkgs.nixfmt-rfc-style ]; };
        kernel = pkgs.mkShell { packages = kernelDeps; };
      }
    );
  };
}

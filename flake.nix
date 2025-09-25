{
  description = "DDK: Nix-based build + nix2container images";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix2container.url = "github:nlewo/nix2container";
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

        # Use network-fetched toolchains and kernel builder
        toolchainFor = import ./nix/toolchains.nix { inherit pkgs lib; };
        kernelBuild = import ./nix/kernel.nix { inherit pkgs lib; };

        # ------------------------------------------------------------
        # Inputs: fetch toolchain and build kernel
        # ------------------------------------------------------------
        mkToolchain = { version }: toolchainFor { inherit version; };

        mkKernel = { ver, srcRev, srcBranch, toolchain, srcSha256 ? null, lto ? null }:
          kernelBuild { inherit ver srcRev srcBranch lto srcSha256; toolchain = toolchain; };

        # ------------------------------------------------------------
        # Base layer and image
        # ------------------------------------------------------------
        # Keep base minimal: only essentials to build kernel modules
        basePkgs = [
          pkgs.bashInteractive
          pkgs.coreutils
          pkgs.findutils
          pkgs.gnugrep
          pkgs.gawk
          pkgs.gnumake
          pkgs.pahole
          pkgs.perl
          pkgs.bc
          pkgs.bison
          pkgs.flex
          pkgs.pkg-config
          pkgs.openssl
          pkgs.ncurses
          pkgs.cacert
        ];

        baseEnv = pkgs.buildEnv {
          name = "ddk-base-env";
          paths = basePkgs;
          ignoreCollisions = true;
          pathsToLink = [ "/bin" ];
        };
        baseLayer = n2c.buildLayer { copyToRoot = baseEnv; };

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

        # ------------------------------------------------------------
        # Layers and images: clang layer, kernel layer, ddk, ddk-dev
        # ------------------------------------------------------------
        mkClangLayer = clangVer:
          let tool = mkToolchain { version = clangVer; };
          in n2c.buildLayer {
            copyToRoot = pkgs.linkFarm "ddk-clang-${clangVer}" [
              { name = "opt/ddk/clang/${clangVer}"; path = "${tool}/clang/${clangVer}"; }
            ];
          };

        mkKernelLayer = ver:
          let
            spec = versions.${ver};
            tool = mkToolchain { version = spec.clang; };
            kdrv = mkKernel {
              ver = ver;
              srcRev = spec.srcRev;
              srcBranch = spec.srcBranch;
              srcSha256 = spec.srcSha256 or null;
              toolchain = "${tool}/clang/${spec.clang}";
            };
          in n2c.buildLayer {
            copyToRoot = pkgs.linkFarm "ddk-tree-${ver}" [
              { name = "opt/ddk/kernel/${ver}"; path = kdrv.kernel; }
              { name = "opt/ddk/src/${ver}"; path = kdrv.source; }
            ];
          };

        # ddk/clang image: only /opt/ddk/clang/<ver>
        mkClangImage = clangVer: n2c.buildImage {
          name = "ghcr.io/ylarod/ddk/clang";
          tag = clangVer;
          layers = [ (mkClangLayer clangVer) ];
          config = {
            Env = [ "DDK_ROOT=/opt/ddk" ];
            Cmd = [ "bash" ];
            Labels = {
              "org.opencontainers.image.title" = "ddk/clang ${clangVer}";
              "org.opencontainers.image.description" = "Android kernel clang toolchain";
              "io.ddk.project" = "ddk";
              "io.ddk.clang.version" = clangVer;
              "io.ddk.variant" = "clang";
            };
          };
        };

        # ddk image: composed from base + ddk/clang + ddk/kernel
        mkDdkImage = ver:
          let
            spec = versions.${ver};
            clangLayer = mkClangLayer spec.clang;
            kernelLayer = mkKernelLayer ver;
          in n2c.buildImage {
            name = "ghcr.io/ylarod/ddk";
            tag = ver;
            layers = [ baseLayer clangLayer kernelLayer ];
            config = {
              Env = [
                "DDK_ROOT=/opt/ddk"
                "CROSS_COMPILE=aarch64-linux-gnu-"
                "ARCH=arm64"
                "LLVM=1"
                "LLVM_IAS=1"
                "KERNEL_SRC=/opt/ddk/kernel/${ver}"
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
                "io.ddk.variant" = "ddk";
              };
            };
          };

        # ddk-dev image: ddk + developer tools
        devTools = [
          pkgs.nix pkgs.less pkgs.vim pkgs.python3Full pkgs.zip pkgs.unzip pkgs.wget
          pkgs.git pkgs.curl pkgs.jq pkgs.gnutar pkgs.gzip pkgs.xz pkgs.util-linux
        ];
        devEnv = pkgs.buildEnv { name = "ddk-dev-env"; paths = devTools; ignoreCollisions = true; pathsToLink = [ "/bin" ]; };
        devLayer = n2c.buildLayer { copyToRoot = devEnv; };

        mkDevImage = ver:
          let
            spec = versions.${ver};
            clangLayer = mkClangLayer spec.clang;
            kernelLayer = mkKernelLayer ver;
          in n2c.buildImage {
            name = "ghcr.io/ylarod/ddk-dev";
            tag = ver;
            layers = [ baseLayer clangLayer kernelLayer devLayer ];
            # initializeNixDatabase = true;
            config = {
              Env = [
                "DDK_ROOT=/opt/ddk"
                "CROSS_COMPILE=aarch64-linux-gnu-"
                "ARCH=arm64"
                "LLVM=1"
                "LLVM_IAS=1"
                "KERNEL_SRC=/opt/ddk/kernel/${ver}"
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

        # ------------------------------------------------------------
        # Exported images
        # ------------------------------------------------------------
        norm = s: lib.replaceStrings [ "-" "." "/" ] [ "_" "_" "_" ] s;

        # ddk (per version) for compatibility: top-level attr by version name
        # Map attribute name (version string) to image; ignore the spec value
        ddkByVer = lib.mapAttrs (ver: _: mkDdkImage ver) versions;

        # Unique clang versions across all entries
        clangVersions = lib.unique (map (spec: spec.clang) (lib.attrValues versions));

        # Flattened, CLI-friendly names (avoid nested sets under packages)
        ddkFlat = lib.listToAttrs (map (ver: { name = "ddk_" + (norm ver); value = mkDdkImage ver; }) (lib.attrNames versions));
        ddkDevFlat = lib.listToAttrs (map (ver: { name = "ddk_dev_" + (norm ver); value = mkDevImage ver; }) (lib.attrNames versions));
        ddkClangFlat = lib.listToAttrs (map (cv: { name = "ddk_clang_" + (norm cv); value = mkClangImage cv; }) clangVersions);
      in
      {
        # Base image
        ddk-base = baseImage;

        # Flattened names, e.g. .#ddk_android14_6_1, .#ddk_dev_android14_6_1, .#ddk_clang_clang_r487747c
      } // ddkFlat // ddkDevFlat // ddkClangFlat // ddkByVer
      // (
        let
          # Debug helpers to narrow failures
          mkToolDbg = ver: mkToolchain { version = ver; };
          mkSrcDbg = ver:
            let spec = versions.${ver}; in
            (kernelBuild {
              ver = ver; srcRev = spec.srcRev; srcBranch = spec.srcBranch;
              srcSha256 = spec.srcSha256 or null; toolchain = baseEnv; # dummy path, we only need to fetch/patch src
            }).source;
        in {
          ddk_debug_toolchain_clang_r416183b = mkToolDbg "clang-r416183b";
          ddk_debug_src_android12_5_10 = mkSrcDbg "android12-5.10";
        }
      )
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

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
        n2c = nix2container.lib pkgs;

        versions = import ./nix/versions.nix { inherit lib; };
        mkToolchain = import ./nix/toolchains.nix { inherit pkgs lib; };
        mkKernel = import ./nix/kernel.nix { inherit pkgs lib; };

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

            optTree = pkgs.linkFarm "ddk-root-${ver}" [
              { name = "opt/ddk/clang/${spec.clang}"; path = "${tool}/clang/${spec.clang}"; }
              { name = "opt/ddk/kdir/${ver}"; path = kdrv.kernel; }
              { name = "opt/ddk/src/${ver}"; path = kdrv.source; }
            ];
          in n2c.buildImage {
            name = "ddk:${ver}";
            copyToRoot = [
              optTree
              pkgs.bashInteractive
              pkgs.coreutils
              pkgs.gnumake
              pkgs.findutils
              pkgs.gnugrep
              pkgs.gawk
              pkgs.gzip
              pkgs.xz
              pkgs.util-linux
              pkgs.dwarves # pahole
            ];
            config = {
              Env = [
                "DDK_ROOT=/opt/ddk"
                "CROSS_COMPILE=aarch64-linux-gnu-"
                "ARCH=arm64"
                "LLVM=1"
                "LLVM_IAS=1"
                "KERNEL_SRC=/opt/ddk/kdir/${ver}"
                "CLANG_PATH=/opt/ddk/clang/${spec.clang}/bin"
                # Note: PATH will be complemented by nix-provided tools already present in image
                "PATH=/opt/ddk/clang/${spec.clang}/bin:/usr/bin:/bin"
              ];
              Cmd = [ "/bin/bash" ];
              Labels = {
                "org.opencontainers.image.title" = "DDK ${ver}";
                "org.opencontainers.image.description" = "Kernel Driver Development Kit for ${ver} (nix-built, offline)";
                "io.ddk.project" = "ddk";
                "io.ddk.android.version" = ver;
                "io.ddk.clang.version" = spec.clang;
                "io.ddk.kernel.src" = ver;
              };
            };
          });

        images = lib.mapAttrs (_: mkImage) versions;
      in
      images
    );

    # A simple dev shell with common tools; does not build kernels.
    devShells = forAllSystems (system:
      let pkgs = import nixpkgs { inherit system; };
      in {
        default = pkgs.mkShell {
          packages = [
            pkgs.git pkgs.curl pkgs.jq pkgs.coreutils pkgs.gnumake pkgs.nixfmt-rfc-style
          ];
        };
      }
    );
  };
}

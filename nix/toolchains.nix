{ pkgs, lib }:

# Build or vendor Android Clang toolchains.
# Preferred: fetch from upstream with fixed-output hash. Fallback: use repo-local clang/<ver> if present.

let
  defaultBranches = {
    "clang-r416183b" = "master-kernel-build-2021";
    "clang-r450784e" = "master-kernel-build-2022";
    "clang-r487747c" = "main-kernel-build-2023";
    "clang-r510928"  = "main-kernel-build-2024";
    "clang-r536225"  = "main-kernel-2025";
  };
in
{ version
, branch ? lib.getAttr version defaultBranches
, sha256s ? {}  # e.g. { "clang-r416183b" = "sha256-..."; }
}:
let
  localPath = ../clang/${version};
in
if builtins.pathExists localPath then
  pkgs.runCommand "${version}-vendor" {
    preferLocalBuild = true;
    allowSubstitutes = false;
  } ''
    mkdir -p "$out"
    cp -a ${localPath}/. "$out/"
  ''
else
  let
    url = "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/${branch}/${version}.tar.gz";
    src = pkgs.fetchurl {
      inherit url;
      # TODO: fill in the correct hash for ${version}
      sha256 = lib.getAttr version sha256s or "0000000000000000000000000000000000000000000000000000";
    };
  in pkgs.runCommand "${version}-fetched" {} ''
    mkdir -p "$out"
    tar -xzf ${src} -C "$out"
  ''


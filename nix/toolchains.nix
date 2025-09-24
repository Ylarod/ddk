{ pkgs, lib }:

# Build or vendor Android Clang toolchains.
# Preferred: fetch from upstream with fixed-output hash. Fallback: use repo-local clang/<ver> if present.

let
  # Unified metadata per toolchain
  metadata = {
    "clang-r416183b" = { branch = "master-kernel-build-2021"; sha256 = "sha256-aYvEWU1gt++qu8m4W4vuRjAvMmIg2p2FslnD+44jLgo="; };
    "clang-r450784e" = { branch = "master-kernel-build-2022"; sha256 = "sha256-EsgydAK2kVP8V068nsjAEzUT37aEto/H41YjlHydAOM="; };
    "clang-r487747c" = { branch = "main-kernel-build-2023";  sha256 = "sha256-MqN/Ybuxh5WCZKFUnuNPjYAV9AP/wr0kd7Xeeen/ddk="; };
    "clang-r510928"  = { branch = "main-kernel-build-2024";  sha256 = "sha256-Z7YgUK6XiqqrE8hp7JZnmZGWXaXmIlJGLQQvbwHBpGc="; };
    "clang-r536225"  = { branch = "main-kernel-2025";       sha256 = "sha256-HulH36XS922nar0xYP0CEHiAatdeWYmz0E4uJjX2N2c="; };
  };
in
{ version
, branch ? null
, sha256s ? {}  # optional external override: { "clang-r*" = "sha256-..."; }
}:
let
  localDir = ../clang/${version};
  haveLocalDir = builtins.pathExists localDir;

  meta = if metadata ? ${version} then metadata.${version} else {};
  effectiveBranch = if branch != null then branch
                    else if meta ? branch then meta.branch
                    else (throw "Missing branch for ${version}; pass 'branch' or extend metadata in nix/toolchains.nix");
  effectiveSha = if sha256s ? ${version} then sha256s.${version}
                 else if meta ? sha256 then meta.sha256 else null;
in
if haveLocalDir then
  pkgs.runCommand "${version}-vendor" {
    preferLocalBuild = true;
    allowSubstitutes = false;
  } ''
    mkdir -p "$out/clang/${version}"
    cp -a ${localDir}/. "$out/clang/${version}/"
  ''
else
  let
    url = "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/${effectiveBranch}/${version}.tar.gz";
    # Use fetchTarball so the hash is computed over unpacked contents (stable across gzip recompression).
    src = builtins.fetchTarball {
      inherit url;
      sha256 = if effectiveSha != null then effectiveSha else (throw "Missing sha256 for ${version}; vendor ../clang/${version} or pass sha256s");
    };
  in pkgs.runCommand "${version}-fetched" {} ''
    mkdir -p "$out/clang"
    ln -s ${src} "$out/clang/${version}"
  ''

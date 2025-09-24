{ pkgs, lib }:

# Always fetch Android Clang toolchains from upstream with fixed-output hash.

let
  # Unified metadata per toolchain
  metadata = {
    "clang-r416183b" = { branch = "master-kernel-build-2021"; sha256 = "sha256-05pr6i8kxq6fxdn5sh6rlr89hq8vxv2n60rw6kyn9cvs2iavkmx3"; };
    "clang-r450784e" = { branch = "master-kernel-build-2022"; sha256 = "sha256-1qzisykwyabfcanvgmfvrgh3mybq6j3i9pw5xg70f75i4db2rz1i"; };
    "clang-r487747c" = { branch = "main-kernel-build-2023";  sha256 = "sha256-1bxlvc6aplrn6lk7ir3wammkbqac3nf5gcx1h0v1cwjybhng0va6"; };
    "clang-r510928"  = { branch = "main-kernel-build-2024";  sha256 = "sha256-195ngpbvf8hvq1y1dwna3zjdmkz31mky0y0rdry2k7r4h5yv429j"; };
    "clang-r536225"  = { branch = "main-kernel-2025";       sha256 = "sha256-1xjzy84a459plvrm5aw3l7zy7qxm77d2nfxagfm0i0vz19bm4rmg"; };
  };
in
{ version
, branch ? null
, sha256s ? {}  # optional external override: { "clang-r*" = "sha256-..."; }
}:
let
  meta = if metadata ? ${version} then metadata.${version} else {};
  effectiveBranch = if branch != null then branch
                    else if meta ? branch then meta.branch
                    else (throw "Missing branch for ${version}; pass 'branch' or extend metadata in nix/toolchains.nix");
  effectiveSha = if sha256s ? ${version} then sha256s.${version}
                 else if meta ? sha256 then meta.sha256 else null;
  url = "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/${effectiveBranch}/${version}.tar.gz";
  # Use fetchTarball so the hash is computed over unpacked contents (stable across gzip recompression).
  src = builtins.fetchTarball {
    inherit url;
    sha256 = if effectiveSha != null then effectiveSha else (throw "Missing sha256 for ${version}; pass sha256 via 'sha256s' or extend metadata");
  };
in pkgs.linkFarm "${version}-fetched" [
  { name = "clang/${version}"; path = src; }
]

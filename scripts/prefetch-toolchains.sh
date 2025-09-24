#!/usr/bin/env bash
set -euo pipefail

# Prefetch Android Clang toolchains and print Nix base32 sha256 for fetchTarball.
# Outputs a copy-pasteable metadata block for nix/toolchains.nix.

declare -A BRANCHES=(
  [clang-r416183b]=master-kernel-build-2021
  [clang-r450784e]=master-kernel-build-2022
  [clang-r487747c]=main-kernel-build-2023
  [clang-r510928]=main-kernel-build-2024
  [clang-r536225]=main-kernel-2025
)

prefetch_base32() {
  local url="$1"
  # Prefer nix-prefetch-url if available (returns base32 directly)
  if command -v nix-prefetch-url >/dev/null 2>&1; then
    nix-prefetch-url --unpack --type sha256 "$url" 2>/dev/null || nix-prefetch-url --unpack "$url"
    return
  fi

  # Fallback to new nix CLI with JSON and to-base32 conversion
  if command -v nix >/dev/null 2>&1; then
    # Try JSON output (Nix 2.15+)
    if nix --extra-experimental-features 'nix-command flakes' store prefetch-file --help >/dev/null 2>&1; then
      local sri
      sri=$(nix --extra-experimental-features 'nix-command flakes' store prefetch-file --unpack --json "$url" \
            | sed -n 's/.*"hash"\s*:\s*"\([^"]\+\)".*/\1/p' | head -n1)
      if [[ -n "$sri" ]]; then
        nix --extra-experimental-features 'nix-command flakes' hash to-base32 "$sri"
        return
      fi
    fi
  fi

  echo "Error: need either nix-prefetch-url or recent nix (with nix-command) to prefetch" >&2
  exit 2
}

echo "# Paste into nix/toolchains.nix (metadata sha256 must be Nix base32)"
echo "metadata = {"
for ver in "${!BRANCHES[@]}"; do
  branch="${BRANCHES[$ver]}"
  url="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/${branch}/${ver}.tar.gz"
  echo "# Prefetching $ver from $branch ..." 1>&2
  b32=$(prefetch_base32 "$url")
  printf '  "%s" = { branch = "%s"; sha256 = "%s"; };\n' "$ver" "$branch" "$b32"
done | sort
echo "};"

echo 1>&2
echo "Done. Above is a stable metadata block with base32 hashes." 1>&2
echo "Tip: If you only need one version, run: nix-prefetch-url --unpack --type sha256 <URL>" 1>&2


#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Kernel Development Environment Setup Script
# ============================================================================
# This script configures VS Code settings for each Android kernel version
# by setting the clangd path according to the mapping.json configuration.
#
# Configuration:
#   ~/.ddk/mapping.json - Target to clang version mapping
#
# Environment Variables:
#   DDK_ROOT - Local DDK installation path (default: /opt/ddk)
#
# ============================================================================

prog=$(basename "$0")
DDK_CONFIG_DIR="$HOME/.ddk"
DDK_MAPPING_JSON="$DDK_CONFIG_DIR/mapping.json"
DDK_ROOT="${DDK_ROOT:-/opt/ddk}"

# ============================================================================
# Utility Functions
# ============================================================================

ensure_dependency() {
  local cmd=$1
  if ! command -v "$cmd" &> /dev/null; then
    echo "Error: '$cmd' is required but not installed" >&2
    echo "Please install '$cmd' and try again" >&2
    exit 1
  fi
}

usage() {
  cat <<EOF
Usage: $prog [options]

Configure VS Code settings for all Android kernel versions.

This script will:
  - Read the mapping.json file
  - For each Android version in the matrix
  - Set clangd.path in .vscode/settings.json to the corresponding clang version

Options:
  -h, --help     Show this help message
  --dry-run      Show what would be done without making changes

Environment Variables:
  DDK_ROOT       DDK installation path (default: /opt/ddk)

Examples:
  $prog
  $prog --dry-run
  DDK_ROOT=/custom/path $prog
EOF
}

# ============================================================================
# JSON Manipulation Functions
# ============================================================================

# Update or add clangd.path in settings.json
# Args:
#   $1 - settings.json file path
#   $2 - clangd path to set
update_settings_json() {
  local settings_file=$1
  local clangd_path=$2

  if [[ -f "$settings_file" ]]; then
    # File exists, update it
    local temp_file
    temp_file=$(mktemp)

    # Use jq to update or add clangd.path
    jq --arg path "$clangd_path" '. + {"clangd.path": $path}' "$settings_file" > "$temp_file"

    # Replace original file
    mv "$temp_file" "$settings_file"
    echo "  ✓ Updated: $settings_file"
  else
    # File doesn't exist, create it
    cat > "$settings_file" <<EOF
{
    "clangd.path": "$clangd_path"
}
EOF
    echo "  ✓ Created: $settings_file"
  fi
}

# ============================================================================
# Main Configuration Function
# ============================================================================

configure_clangd() {
  local dry_run=${1:-false}

  # Check if mapping.json exists
  if [[ ! -f "$DDK_MAPPING_JSON" ]]; then
    echo "Error: mapping.json not found at $DDK_MAPPING_JSON" >&2
    echo "Please run 'ddk update' first to download mapping.json" >&2
    exit 1
  fi

  # Check if DDK_ROOT exists
  if [[ ! -d "$DDK_ROOT" ]]; then
    echo "Error: DDK_ROOT directory not found: $DDK_ROOT" >&2
    exit 1
  fi

  echo "Configuring clangd for Android kernel versions..."
  echo "DDK_ROOT: $DDK_ROOT"
  echo "Mapping: $DDK_MAPPING_JSON"
  echo ""

  # Parse matrix from mapping.json
  local matrix_count
  matrix_count=$(jq '.matrix | length' "$DDK_MAPPING_JSON")

  local configured_count=0
  local skipped_count=0

  for ((i=0; i<matrix_count; i++)); do
    local android clang
    android=$(jq -r ".matrix[$i].android" "$DDK_MAPPING_JSON")
    clang=$(jq -r ".matrix[$i].clang" "$DDK_MAPPING_JSON")

    echo "Processing: $android -> $clang"

    # Check if directories exist
    local src_dir="$DDK_ROOT/src/$android"
    local clang_dir="$DDK_ROOT/clang/$clang"
    local clangd_bin="$clang_dir/bin/clangd"

    if [[ ! -d "$src_dir" ]]; then
      echo "  ⚠ Skipped: source directory not found: $src_dir"
      skipped_count=$((skipped_count + 1))
      echo ""
      continue
    fi

    if [[ ! -d "$clang_dir" ]]; then
      echo "  ⚠ Skipped: clang directory not found: $clang_dir"
      skipped_count=$((skipped_count + 1))
      echo ""
      continue
    fi

    if [[ ! -f "$clangd_bin" ]]; then
      echo "  ⚠ Warning: clangd binary not found: $clangd_bin"
      echo "  Creating settings.json anyway..."
    fi

    # Create .vscode directory if it doesn't exist
    local vscode_dir="$src_dir/.vscode"
    local settings_file="$vscode_dir/settings.json"

    if [[ "$dry_run" == "true" ]]; then
      echo "  [DRY RUN] Would configure: $settings_file"
      echo "  [DRY RUN] clangd.path = $clangd_bin"
    else
      mkdir -p "$vscode_dir"
      update_settings_json "$settings_file" "$clangd_bin"
    fi

    configured_count=$((configured_count + 1))
    echo ""
  done

  echo "=========================================="
  echo "Summary:"
  echo "  Configured: $configured_count"
  echo "  Skipped: $skipped_count"
  echo "=========================================="

  if [[ "$dry_run" == "true" ]]; then
    echo ""
    echo "This was a dry run. No changes were made."
    echo "Run without --dry-run to apply changes."
  fi
}

# ============================================================================
# Main Function
# ============================================================================

main() {
  # Ensure jq is installed
  ensure_dependency jq

  # Parse arguments
  local dry_run=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      --dry-run)
        dry_run=true
        shift
        ;;
      *)
        echo "Error: Unknown option: $1" >&2
        usage
        exit 1
        ;;
    esac
  done

  # Run configuration
  configure_clangd "$dry_run"
}

# ============================================================================
# Entry Point
# ============================================================================

main "$@"

#!/bin/bash

set -e

# Environment variables
DDK_ROOT=/opt/ddk
SRC_BASE_DIR=$DDK_ROOT/src
KDIR_BASE_DIR=$DDK_ROOT/kdir
CLANG_BASE_DIR=$DDK_ROOT/clang

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREBUILTS_DIR="$(realpath "$SCRIPT_DIR/../prebuilts")"

# Print functions
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    if ! command -v zstd &> /dev/null; then
        print_error "zstd command not found, please install zstd first"
        exit 1
    fi
}

# Setup DDK root directory
setup_ddk_root() {
    local current_user=$(whoami)
    local current_group=$(id -gn)

    if [ ! -d "$DDK_ROOT" ]; then
        print_info "$DDK_ROOT does not exist, creating..."
        sudo mkdir -p $DDK_ROOT
        print_info "Directory created successfully"
    else
        print_info "$DDK_ROOT already exists"
    fi

    # Check if ownership change is needed
    local owner=$(stat -f "%Su" "$DDK_ROOT" 2>/dev/null || stat -c "%U" "$DDK_ROOT" 2>/dev/null)
    local group=$(stat -f "%Sg" "$DDK_ROOT" 2>/dev/null || stat -c "%G" "$DDK_ROOT" 2>/dev/null)

    if [ "$owner" != "$current_user" ] || [ "$group" != "$current_group" ]; then
        print_info "Changing $DDK_ROOT owner to $current_user:$current_group..."
        sudo chown -R $current_user:$current_group $DDK_ROOT
    else
        print_info "$DDK_ROOT already owned by $current_user:$current_group, skipping"
    fi
}

# Extract archives for a specific component
extract_archives() {
    local component=$1
    local base_dir=$2
    local prefix=$3

    print_info "Decompressing $component files..."
    mkdir -p $base_dir

    for tarfile in "$PREBUILTS_DIR/$component"/*.tar.zst; do
        if [ -f "$tarfile" ]; then
            filename=$(basename "$tarfile")
            dirname="${filename%.tar.zst}"

            # Remove prefix if specified
            if [ -n "$prefix" ]; then
                dirname="${dirname#$prefix}"
            fi

            target_dir="$base_dir/$dirname"

            if [ -d "$target_dir" ]; then
                print_warn "Skipping $dirname (already exists)"
            else
                print_info "Extracting $filename..."
                tar -xf "$tarfile" -C $base_dir
            fi
        fi
    done
}

# Check if a file is Mach-O format
is_macho() {
    local file=$1
    if [ ! -f "$file" ]; then
        return 1
    fi
    file "$file" | grep -q "Mach-O"
    return $?
}

# Main function
main() {
    print_info "Starting DDK installation..."

    # Check prerequisites
    check_prerequisites

    # Setup DDK root directory
    setup_ddk_root

    # Extract all components
    extract_archives "clang" "$CLANG_BASE_DIR" ""
    extract_archives "src" "$SRC_BASE_DIR" "src."
    extract_archives "kdir" "$KDIR_BASE_DIR" "kdir."

    print_info "All files extracted successfully!"
    print_info "Installation directory: $DDK_ROOT"

    print_info "Installation completed successfully!"
}

# Run main function
main


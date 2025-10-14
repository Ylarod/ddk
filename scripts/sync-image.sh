#!/usr/bin/env bash
set -euo pipefail

# === Default Configuration ===
MAPPING_FILE="${MAPPING_FILE:-./mapping.json}"
SRC_REGISTRY_TYPE=""
DST_REGISTRY_TYPE=""
PROJECT="all"
DRY_RUN=false
USE_DATE=""
NEW_DATE=""
DEFAULT_DATE="$(date +%Y%m%d)"

# === Parse command line arguments ===
usage() {
  cat << EOF
Usage: $0 [OPTIONS]

Sync container images between registries using skopeo.

OPTIONS:
  -s, --src <registry>     Source registry type (github|docker|cnb) [REQUIRED]
  -d, --dst <registry>     Destination registry type (github|docker|cnb) [REQUIRED]
  -p, --project <name>     Project to sync (ddk|ddk-clang|all) [default: all]
  -m, --mapping <file>     Path to mapping.json file [default: ./mapping.json]
  --date <date>            Sync images with date tag (src:ver-date -> dst:ver-date)
  --new-date <date>        Add new date tag to destination (src:ver -> dst:ver-newdate)
  --dry-run                Show what would be synced without actually syncing
  -h, --help               Show this help message

TAG MODES:
  No date flags:           src:ver -> dst:ver
  --date 20250101:         src:ver-20250101 -> dst:ver-20250101
  --new-date 20250101:     src:ver -> dst:ver-20250101

EXAMPLES:
  $0 -s github -d docker                          # Sync: src:ver -> dst:ver
  $0 -s github -d cnb --date 20250101             # Sync: src:ver-20250101 -> dst:ver-20250101
  $0 -s github -d docker --new-date 20250101      # Sync: src:ver -> dst:ver-20250101
  $0 -s github -d cnb -p ddk --dry-run            # Preview sync for ddk only

EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case $1 in
    -s|--src)
      SRC_REGISTRY_TYPE="$2"
      shift 2
      ;;
    -d|--dst)
      DST_REGISTRY_TYPE="$2"
      shift 2
      ;;
    -p|--project)
      PROJECT="$2"
      shift 2
      ;;
    -m|--mapping)
      MAPPING_FILE="$2"
      shift 2
      ;;
    --date)
      USE_DATE="$2"
      shift 2
      ;;
    --new-date)
      NEW_DATE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Error: Unknown option: $1"
      usage
      ;;
  esac
done

# === Functions ===

# Check if command exists
check_command() {
  local cmd="$1"
  local install_hint="$2"

  if ! command -v "$cmd" &> /dev/null; then
    echo "Error: $cmd not found. Please install it first."
    echo "$install_hint"
    exit 1
  fi
}

# Validate registry type
validate_registry_type() {
  local registry_type="$1"
  local registry_label="$2"

  if ! jq -e ".registry.ddk.$registry_type" "$MAPPING_FILE" > /dev/null 2>&1; then
    echo "Error: Invalid $registry_label registry type: $registry_type"
    echo "Valid types: github, docker, cnb"
    exit 1
  fi
}

# Check dependencies
check_command "skopeo" "   macOS: brew install skopeo
   Linux: apt install skopeo / yum install skopeo"

check_command "jq" "   macOS: brew install jq
   Linux: apt install jq / yum install jq"

if [ ! -f "$MAPPING_FILE" ]; then
  echo "Error: Mapping file not found: $MAPPING_FILE"
  exit 1
fi

# Check required parameters
if [[ -z "$SRC_REGISTRY_TYPE" ]]; then
  echo "Error: Source registry type is required. Use -s or --src"
  echo "Run '$0 --help' for usage information"
  exit 1
fi

if [[ -z "$DST_REGISTRY_TYPE" ]]; then
  echo "Error: Destination registry type is required. Use -d or --dst"
  echo "Run '$0 --help' for usage information"
  exit 1
fi

# Validate registry types
validate_registry_type "$SRC_REGISTRY_TYPE" "source"
validate_registry_type "$DST_REGISTRY_TYPE" "destination"

# Validate project
if [[ "$PROJECT" != "all" && "$PROJECT" != "ddk" && "$PROJECT" != "ddk-clang" ]]; then
  echo "Error: Invalid project: $PROJECT"
  echo "Valid projects: ddk, ddk-clang, all"
  exit 1
fi

# Validate date options (cannot use both)
if [[ -n "$USE_DATE" && -n "$NEW_DATE" ]]; then
  echo "Error: Cannot use both --date and --new-date at the same time"
  exit 1
fi

echo "Registry Image Sync Tool"
echo "   Source: $SRC_REGISTRY_TYPE"
echo "   Destination: $DST_REGISTRY_TYPE"
echo "   Project: $PROJECT"
echo "   Mapping: $MAPPING_FILE"

# Determine tag mode
if [[ -n "$USE_DATE" ]]; then
  echo "   Tag Mode: src:ver-${USE_DATE} -> dst:ver-${USE_DATE}"
elif [[ -n "$NEW_DATE" ]]; then
  echo "   Tag Mode: src:ver -> dst:ver-${NEW_DATE}"
else
  echo "   Tag Mode: src:ver -> dst:ver"
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "   Mode: DRY RUN (no actual sync will be performed)"
fi
echo

# Function: sync image
sync_image() {
  local src_image="$1"
  local dst_image="$2"
  local base_tag="$3"

  local src_tag="$base_tag"
  local dst_tag="$base_tag"

  # Apply date logic based on flags
  if [[ -n "$USE_DATE" ]]; then
    # Mode: src:ver-date -> dst:ver-date
    src_tag="${base_tag}-${USE_DATE}"
    dst_tag="${base_tag}-${USE_DATE}"
  elif [[ -n "$NEW_DATE" ]]; then
    # Mode: src:ver -> dst:ver-newdate
    src_tag="$base_tag"
    dst_tag="${base_tag}-${NEW_DATE}"
  else
    # Mode: src:ver -> dst:ver
    src_tag="$base_tag"
    dst_tag="$base_tag"
  fi

  local src_full="${src_image}:${src_tag}"
  local dst_full="${dst_image}:${dst_tag}"

  echo "==> Syncing: ${src_full}"
  echo "     -> ${dst_full}"

  if [[ "$DRY_RUN" == true ]]; then
    echo "    [DRY RUN] Would sync to ${dst_full}"
    echo
    return 0
  fi

  # Use skopeo to copy directly between registries
  if skopeo copy "docker://${src_full}" "docker://${dst_full}"; then
    echo "    [OK] Synced to ${dst_full}"
  else
    echo "    [FAIL] Failed to sync ${dst_full}"
    return 1
  fi

  echo
}

# Get registry URLs from mapping.json
SRC_REGISTRY_DDK=$(jq -r ".registry.ddk.$SRC_REGISTRY_TYPE" "$MAPPING_FILE")
DST_REGISTRY_DDK=$(jq -r ".registry.ddk.$DST_REGISTRY_TYPE" "$MAPPING_FILE")
SRC_REGISTRY_CLANG=$(jq -r ".registry[\"ddk-clang\"].$SRC_REGISTRY_TYPE" "$MAPPING_FILE")
DST_REGISTRY_CLANG=$(jq -r ".registry[\"ddk-clang\"].$DST_REGISTRY_TYPE" "$MAPPING_FILE")

echo "   DDK: $SRC_REGISTRY_DDK -> $DST_REGISTRY_DDK"
echo "   Clang: $SRC_REGISTRY_CLANG -> $DST_REGISTRY_CLANG"
echo

# Process clang images
if [[ "$PROJECT" == "all" || "$PROJECT" == "ddk-clang" ]]; then
  echo "Processing clang images..."
  clang_versions=$(jq -r '.clang[].version' "$MAPPING_FILE")
  clang_branches=$(jq -r '.clang[].branch' "$MAPPING_FILE")

  # Convert to arrays
  IFS=$'\n' read -d '' -r -a clang_version_array <<< "$clang_versions" || true
  IFS=$'\n' read -d '' -r -a clang_branch_array <<< "$clang_branches" || true

  for i in "${!clang_version_array[@]}"; do
    version="${clang_version_array[$i]}"
    branch="${clang_branch_array[$i]}"

    echo "[Clang] ${version} (${branch})"
    sync_image "$SRC_REGISTRY_CLANG" "$DST_REGISTRY_CLANG" "$version" || echo "WARNING: Failed to sync ${version}"
  done
fi

# Process android images
if [[ "$PROJECT" == "all" || "$PROJECT" == "ddk" ]]; then
  echo "Processing android (ddk) images..."
  android_names=$(jq -r '.android[].name' "$MAPPING_FILE")

  # Convert to arrays
  IFS=$'\n' read -d '' -r -a android_name_array <<< "$android_names" || true

  for i in "${!android_name_array[@]}"; do
    name="${android_name_array[$i]}"

    echo "[Android] ${name} -> ${name}"
    sync_image "$SRC_REGISTRY_DDK" "$DST_REGISTRY_DDK" "$name" || echo "WARNING: Failed to sync ${name}"
  done
fi

echo
if [[ "$DRY_RUN" == true ]]; then
  echo "[DRY RUN] All images would be synced from registry to registry."
else
  echo "All images have been synced from registry to registry."
fi

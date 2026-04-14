#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(cd -- "$(dirname -- "$0")" && pwd)/common.sh"

setup_local_tooling_env

extension_id="${SHORTY_CHROME_EXTENSION_ID:-}"
browsers="${SHORTY_BROWSER_TARGETS:-chrome}"
mode="install"

while [ $# -gt 0 ]; do
  case "$1" in
  --extension-id)
    extension_id="$2"
    shift 2
    ;;
  --browsers)
    browsers="$2"
    shift 2
    ;;
  --uninstall)
    mode="uninstall"
    shift
    ;;
  *)
    printf 'Unknown argument: %s\n' "$1" >&2
    exit 2
    ;;
  esac
done

if [ "$mode" = "uninstall" ]; then
  uv run python -m scripts.tooling.browser_manifest uninstall \
    --browsers "$browsers"
  exit 0
fi

if [ -z "$extension_id" ]; then
  printf 'Usage: just install-browser-bridge EXTENSION_ID=<chrome-extension-id> [BROWSERS=chrome]\n' >&2
  exit 2
fi

generate_workspace

derived_data_path="$REPO_ROOT/$BRIDGE_DERIVED_DATA"
xcodebuild \
  -workspace "$REPO_ROOT/$APP_WORKSPACE" \
  -scheme "$BRIDGE_SCHEME" \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath "$derived_data_path" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  COMPILATION_CACHE_ENABLE_CACHING=NO \
  COMPILATION_CACHE_ENABLE_PLUGIN=NO \
  build

bridge_product="$derived_data_path/Build/Products/Release/$BRIDGE_SCHEME"
install_dir="$REPO_ROOT/.build/browser-bridge"
bridge_path="$install_dir/shorty-bridge"

if [ ! -x "$bridge_product" ]; then
  printf 'Built bridge executable not found: %s\n' "$bridge_product" >&2
  exit 1
fi

mkdir -p "$install_dir"
cp "$bridge_product" "$bridge_path"
chmod +x "$bridge_path"

uv run python -m scripts.tooling.browser_manifest install \
  --extension-id "$extension_id" \
  --bridge-path "$bridge_path" \
  --browsers "$browsers"

printf 'Installed bridge executable: %s\n' "$bridge_path"

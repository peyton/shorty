#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(cd -- "$(dirname -- "$0")" && pwd)/common.sh"

setup_local_tooling_env

extension_id="${SHORTY_CHROME_EXTENSION_ID:-}"
manifest_dir="${CHROME_NATIVE_MESSAGING_HOSTS_DIR:-$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts}"

while [ $# -gt 0 ]; do
  case "$1" in
  --extension-id)
    extension_id="$2"
    shift 2
    ;;
  --manifest-dir)
    manifest_dir="$2"
    shift 2
    ;;
  *)
    printf 'Unknown argument: %s\n' "$1" >&2
    exit 2
    ;;
  esac
done

if [ -z "$extension_id" ]; then
  printf 'Usage: just install-browser-bridge EXTENSION_ID=<chrome-extension-id>\n' >&2
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
manifest_path="$manifest_dir/com.shorty.browser_bridge.json"

if [ ! -x "$bridge_product" ]; then
  printf 'Built bridge executable not found: %s\n' "$bridge_product" >&2
  exit 1
fi

mkdir -p "$install_dir" "$manifest_dir"
cp "$bridge_product" "$bridge_path"
chmod +x "$bridge_path"

cat >"$manifest_path" <<JSON
{
  "name": "com.shorty.browser_bridge",
  "description": "Shorty browser context bridge",
  "path": "$bridge_path",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://$extension_id/"
  ]
}
JSON

printf 'Installed bridge executable: %s\n' "$bridge_path"
printf 'Installed native messaging manifest: %s\n' "$manifest_path"

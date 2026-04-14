#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(cd -- "$(dirname -- "$0")" && pwd)/common.sh"

setup_local_tooling_env
generate_workspace

configuration="Release"
derived_data_path="$REPO_ROOT/$SCREENSHOT_DERIVED_DATA"
result_bundle_path="$REPO_ROOT/.build/marketing-screenshots.xcresult"
output_dir="$REPO_ROOT/web/assets/screenshots"

mkdir -p "$derived_data_path" "$output_dir" "$(dirname "$result_bundle_path")"
rm -rf "$result_bundle_path"

printf 'DERIVED_DATA=%s\n' "$derived_data_path"
printf 'RESULT_BUNDLE=%s\n' "$result_bundle_path"
printf 'SCREENSHOT_OUTPUT=%s\n' "$output_dir"

xcodebuild \
  -workspace "$REPO_ROOT/$APP_WORKSPACE" \
  -scheme "$SCREENSHOT_SCHEME" \
  -configuration "$configuration" \
  -destination "platform=macOS" \
  -derivedDataPath "$derived_data_path" \
  -resultBundlePath "$result_bundle_path" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  COMPILATION_CACHE_ENABLE_CACHING=NO \
  COMPILATION_CACHE_ENABLE_PLUGIN=NO \
  build

tool_path="$derived_data_path/Build/Products/$configuration/$SCREENSHOT_SCHEME"
if [ ! -x "$tool_path" ]; then
  printf 'Screenshot tool not found: %s\n' "$tool_path" >&2
  exit 1
fi

DYLD_FRAMEWORK_PATH="$derived_data_path/Build/Products/$configuration" "$tool_path" "$output_dir"

assert_dimensions() {
  local file="$1"
  local expected_width="$2"
  local expected_height="$3"
  local path="$output_dir/$file"

  if [ ! -f "$path" ]; then
    printf 'Missing screenshot: %s\n' "$path" >&2
    exit 1
  fi

  local actual_width actual_height
  actual_width="$(sips -g pixelWidth "$path" 2>/dev/null | awk '/pixelWidth/ { print $2 }')"
  actual_height="$(sips -g pixelHeight "$path" 2>/dev/null | awk '/pixelHeight/ { print $2 }')"

  if [ "$actual_width" != "$expected_width" ] || [ "$actual_height" != "$expected_height" ]; then
    printf 'Unexpected dimensions for %s: got %sx%s expected %sx%s\n' \
      "$file" "$actual_width" "$actual_height" "$expected_width" "$expected_height" >&2
    exit 1
  fi
}

assert_dimensions native-settings-shortcuts.png 1680 1320
assert_dimensions native-settings-apps.png 1680 1320
assert_dimensions native-status-popover.png 1000 1280
assert_dimensions native-status-permission.png 1000 1280
assert_dimensions native-status-paused.png 1000 1280
assert_dimensions native-status-no-adapter.png 1000 1280
assert_dimensions app-store-shortcuts.png 2880 1800
assert_dimensions app-store-apps.png 2880 1800
assert_dimensions app-store-setup.png 2880 1800
assert_dimensions web-hero.png 1600 1000
assert_dimensions web-apps.png 1600 1000
assert_dimensions web-setup.png 1600 1000

printf 'Marketing screenshot validation passed.\n'

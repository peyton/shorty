#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(cd -- "$(dirname -- "$0")" && pwd)/common.sh"

setup_local_tooling_env
generate_workspace

derived_data_path="$REPO_ROOT/.DerivedData/app-store"
result_bundle_path="$REPO_ROOT/.build/app-store-build.xcresult"
rm -rf "$result_bundle_path"

xcodebuild \
  -workspace "$REPO_ROOT/$APP_WORKSPACE" \
  -scheme "ShortyAppStore" \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath "$derived_data_path" \
  -resultBundlePath "$result_bundle_path" \
  CODE_SIGNING_ALLOWED="${SHORTY_APP_STORE_CODE_SIGNING_ALLOWED:-NO}" \
  CODE_SIGNING_REQUIRED="${SHORTY_APP_STORE_CODE_SIGNING_REQUIRED:-NO}" \
  COMPILATION_CACHE_ENABLE_CACHING=NO \
  COMPILATION_CACHE_ENABLE_PLUGIN=NO \
  build

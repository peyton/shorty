#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(cd -- "$(dirname -- "$0")" && pwd)/common.sh"

setup_local_tooling_env
ensure_workspace_generated

result_bundle_path="$REPO_ROOT/.build/test-app.xcresult"
xcodebuild_log_path="$REPO_ROOT/.build/test-app.xcodebuild.log"
rm -rf "$result_bundle_path"

set +e
xcodebuild \
  test \
  -workspace "$REPO_ROOT/$APP_WORKSPACE" \
  -scheme "$TEST_SCHEME" \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath "$REPO_ROOT/$TEST_DERIVED_DATA" \
  -resultBundlePath "$result_bundle_path" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  COMPILATION_CACHE_ENABLE_CACHING=NO \
  COMPILATION_CACHE_ENABLE_PLUGIN=NO 2>&1 | tee "$xcodebuild_log_path"
status=${PIPESTATUS[0]}
set -e

exit "$status"

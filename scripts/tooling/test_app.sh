#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(cd -- "$(dirname -- "$0")" && pwd)/common.sh"

setup_local_tooling_env
ensure_workspace_generated

result_bundle_path="$REPO_ROOT/.build/test-app.xcresult"
xcodebuild_log_path="$REPO_ROOT/.build/test-app.xcodebuild.log"
rm -rf "$result_bundle_path" "$REPO_ROOT/.build/test-app-"*.xcresult
: >"$xcodebuild_log_path"

if [ -n "${TEST_SCHEMES:-}" ]; then
  read -r -a test_schemes <<<"$TEST_SCHEMES"
else
  test_schemes=("${TEST_SCHEME:-ShortyCore}" "Shorty")
fi

status=0
for scheme in "${test_schemes[@]}"; do
  scheme_result_bundle_path="$REPO_ROOT/.build/test-app-$scheme.xcresult"
  printf '\n=== Testing %s ===\n' "$scheme" | tee -a "$xcodebuild_log_path"
  rm -rf "$scheme_result_bundle_path"

  set +e
  xcodebuild \
    test \
    -workspace "$REPO_ROOT/$APP_WORKSPACE" \
    -scheme "$scheme" \
    -configuration Debug \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "$REPO_ROOT/$TEST_DERIVED_DATA" \
    -resultBundlePath "$scheme_result_bundle_path" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    COMPILATION_CACHE_ENABLE_CACHING=NO \
    COMPILATION_CACHE_ENABLE_PLUGIN=NO 2>&1 | tee -a "$xcodebuild_log_path"
  scheme_status=${PIPESTATUS[0]}
  set -e

  if [ "$scheme_status" -ne 0 ]; then
    status="$scheme_status"
  fi
done

exit "$status"

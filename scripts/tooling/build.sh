#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(cd -- "$(dirname -- "$0")" && pwd)/common.sh"

setup_local_tooling_env

configuration="Release"
derived_data_path="$REPO_ROOT/$BUILD_DERIVED_DATA"
result_bundle_path="$REPO_ROOT/.build/build.xcresult"
run_generate=1

while [ $# -gt 0 ]; do
  case "$1" in
  --configuration)
    configuration="$2"
    shift 2
    ;;
  --derived-data-path)
    derived_data_path="$2"
    shift 2
    ;;
  --result-bundle-path)
    result_bundle_path="$2"
    shift 2
    ;;
  --skip-generate)
    run_generate=0
    shift
    ;;
  *)
    printf 'Unknown argument: %s\n' "$1" >&2
    exit 2
    ;;
  esac
done

if [ "$run_generate" -eq 1 ]; then
  generate_workspace
fi

mkdir -p "$(dirname "$derived_data_path")" "$(dirname "$result_bundle_path")"
rm -rf "$result_bundle_path"

printf 'DERIVED_DATA=%s\n' "$derived_data_path"
printf 'RESULT_BUNDLE=%s\n' "$result_bundle_path"

xcodebuild \
  -workspace "$REPO_ROOT/$APP_WORKSPACE" \
  -scheme "$APP_SCHEME" \
  -configuration "$configuration" \
  -destination "platform=macOS" \
  -derivedDataPath "$derived_data_path" \
  -resultBundlePath "$result_bundle_path" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  COMPILATION_CACHE_ENABLE_CACHING=NO \
  COMPILATION_CACHE_ENABLE_PLUGIN=NO \
  build

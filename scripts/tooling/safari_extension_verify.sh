#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(cd -- "$(dirname -- "$0")" && pwd)/common.sh"

setup_local_tooling_env

app_path="$REPO_ROOT/$BUILD_DERIVED_DATA/Build/Products/Release/$APP_PRODUCT_NAME.app"
require_codesign=0

while [ $# -gt 0 ]; do
  case "$1" in
  --app-path)
    app_path="$2"
    shift 2
    ;;
  --require-codesign)
    require_codesign=1
    shift
    ;;
  *)
    printf 'Unknown argument: %s\n' "$1" >&2
    exit 2
    ;;
  esac
done

args=(--app-path "$app_path")
if [ "$require_codesign" -eq 1 ]; then
  args+=(--require-codesign)
fi

uv run python -m scripts.tooling.safari_extension_verify "${args[@]}"

#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(cd -- "$(dirname -- "$0")" && pwd)/common.sh"

setup_local_tooling_env

version=""

while [ $# -gt 0 ]; do
  case "$1" in
  --version)
    version="$2"
    shift 2
    ;;
  *)
    printf 'Unknown argument: %s\n' "$1" >&2
    exit 2
    ;;
  esac
done

if [ -z "$version" ]; then
  printf 'Usage: just release-preflight VERSION=<version>\n' >&2
  exit 2
fi

app_path="$REPO_ROOT/$BUILD_DERIVED_DATA/Build/Products/Release/$APP_PRODUCT_NAME.app"
uv run python -m scripts.tooling.release_preflight \
  --version "$version" \
  --app-path "$app_path"

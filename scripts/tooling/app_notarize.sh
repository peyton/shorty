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
  printf 'Usage: just app-notarize VERSION=<version>\n' >&2
  exit 2
fi

archive_path="$REPO_ROOT/.build/releases/shorty-$version-macos.zip"
app_path="$REPO_ROOT/$BUILD_DERIVED_DATA/Build/Products/Release/$APP_PRODUCT_NAME.app"

if [ ! -f "$archive_path" ]; then
  printf 'Release archive not found: %s\n' "$archive_path" >&2
  printf 'Run: just app-package VERSION=%s\n' "$version" >&2
  exit 1
fi

if [ ! -d "$app_path" ]; then
  printf 'Built app not found for stapling: %s\n' "$app_path" >&2
  exit 1
fi

if [ -n "${NOTARYTOOL_PROFILE:-}" ]; then
  xcrun notarytool submit "$archive_path" \
    --keychain-profile "$NOTARYTOOL_PROFILE" \
    --wait
else
  missing=0
  for name in APPLE_ID APPLE_TEAM_ID APPLE_APP_SPECIFIC_PASSWORD; do
    if [ -z "${!name:-}" ]; then
      printf 'Missing required notarization environment variable: %s\n' "$name" >&2
      missing=1
    fi
  done
  if [ "$missing" -ne 0 ]; then
    printf 'Set NOTARYTOOL_PROFILE or APPLE_ID, APPLE_TEAM_ID, and APPLE_APP_SPECIFIC_PASSWORD.\n' >&2
    exit 2
  fi

  xcrun notarytool submit "$archive_path" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --wait
fi

xcrun stapler staple "$app_path"

uv run python -m scripts.tooling.package_app \
  --version "$version" \
  --app-path "$app_path" \
  --output-dir "$REPO_ROOT/.build/releases"

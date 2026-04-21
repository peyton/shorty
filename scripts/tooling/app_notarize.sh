#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(cd -- "$(dirname -- "$0")" && pwd)/common.sh"

setup_local_tooling_env

version=""
artifact_label=""

while [ $# -gt 0 ]; do
  case "$1" in
  --version)
    version="$2"
    shift 2
    ;;
  --artifact-label)
    artifact_label="$2"
    shift 2
    ;;
  *)
    printf 'Unknown argument: %s\n' "$1" >&2
    exit 2
    ;;
  esac
done

if [ -z "$version" ]; then
  printf 'Usage: just app-notarize VERSION=<version> [ARTIFACT_LABEL=<label>]\n' >&2
  exit 2
fi

archive_label="${artifact_label:-$version}"
archive_path="$REPO_ROOT/.build/releases/shorty-$archive_label-macos.zip"
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
  materialize_app_store_connect_key_if_needed

  missing=0
  for name in SHORTY_APP_STORE_CONNECT_KEY_PATH SHORTY_APP_STORE_CONNECT_KEY_ID SHORTY_APP_STORE_CONNECT_ISSUER_ID; do
    if [ -z "${!name:-}" ]; then
      printf 'Missing required notarization environment variable: %s\n' "$name" >&2
      missing=1
    fi
  done
  if [ "$missing" -ne 0 ]; then
    printf 'Set NOTARYTOOL_PROFILE or SHORTY_APP_STORE_CONNECT_KEY_PATH, SHORTY_APP_STORE_CONNECT_KEY_ID, and SHORTY_APP_STORE_CONNECT_ISSUER_ID.\n' >&2
    printf 'For CI, set SHORTY_APP_STORE_CONNECT_API_KEY_P8 to the raw .p8 contents.\n' >&2
    printf 'The App Store Connect API key must be a Team key for notarytool.\n' >&2
    exit 2
  fi
  if [ ! -f "$SHORTY_APP_STORE_CONNECT_KEY_PATH" ]; then
    printf 'App Store Connect API key file not found: %s\n' "$SHORTY_APP_STORE_CONNECT_KEY_PATH" >&2
    exit 2
  fi

  xcrun notarytool submit "$archive_path" \
    --key "$SHORTY_APP_STORE_CONNECT_KEY_PATH" \
    --key-id "$SHORTY_APP_STORE_CONNECT_KEY_ID" \
    --issuer "$SHORTY_APP_STORE_CONNECT_ISSUER_ID" \
    --wait
fi

xcrun stapler staple "$app_path"

package_args=(
  --version "$version"
  --app-path "$app_path"
  --output-dir "$REPO_ROOT/.build/releases"
)
if [ -n "$artifact_label" ]; then
  package_args+=(--artifact-label "$artifact_label")
fi

uv run python -m scripts.tooling.package_app "${package_args[@]}"

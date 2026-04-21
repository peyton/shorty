#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(cd -- "$(dirname -- "$0")" && pwd)/common.sh"

setup_local_tooling_env

version=""
build_number=""
archive_path=""

while [ $# -gt 0 ]; do
  case "$1" in
  --version)
    version="$2"
    shift 2
    ;;
  --build-number)
    build_number="$2"
    shift 2
    ;;
  --archive-path)
    archive_path="$2"
    shift 2
    ;;
  *)
    printf 'Unknown argument: %s\n' "$1" >&2
    exit 2
    ;;
  esac
done

if [ -z "$version" ] || [ -z "$build_number" ]; then
  printf 'Usage: just app-store-archive VERSION=<version> BUILD_NUMBER=<number>\n' >&2
  exit 2
fi

validate_app_version "$version"
validate_apple_build_number "$build_number"
require_app_store_archive_signing

if [ -z "$archive_path" ]; then
  archive_path="$REPO_ROOT/.build/app-store/ShortyAppStore-$version-$build_number.xcarchive"
fi

export SHORTY_MARKETING_VERSION="$version"
export SHORTY_BUILD_NUMBER="$build_number"
sync_tuist_shorty_version_env
generate_workspace

auth_args=()
if [ "${SHORTY_APP_STORE_ALLOW_LOCAL_SIGNING:-}" != "1" ] &&
  app_store_connect_auth_args >/dev/null; then
  auth_args=(
    -allowProvisioningUpdates
    -authenticationKeyPath "$SHORTY_APP_STORE_CONNECT_KEY_PATH"
    -authenticationKeyID "$SHORTY_APP_STORE_CONNECT_KEY_ID"
    -authenticationKeyIssuerID "$SHORTY_APP_STORE_CONNECT_ISSUER_ID"
  )
fi

mkdir -p "$(dirname "$archive_path")"
rm -rf "$archive_path"

xcodebuild \
  -workspace "$REPO_ROOT/$APP_WORKSPACE" \
  -scheme "ShortyAppStore" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$archive_path" \
  "${auth_args[@]}" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=YES \
  COMPILATION_CACHE_ENABLE_CACHING=NO \
  COMPILATION_CACHE_ENABLE_PLUGIN=NO \
  archive

printf 'Created %s\n' "$archive_path"

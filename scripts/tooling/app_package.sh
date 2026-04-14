#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(cd -- "$(dirname -- "$0")" && pwd)/common.sh"

setup_local_tooling_env

artifact_label=""
version=""

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
  printf 'Usage: just app-package VERSION=<version> [ARTIFACT_LABEL=<label>]\n' >&2
  exit 2
fi

"$TOOLING_DIR/build.sh" --configuration Release

app_path="$REPO_ROOT/$BUILD_DERIVED_DATA/Build/Products/Release/$APP_PRODUCT_NAME.app"
if [ ! -d "$app_path" ]; then
  printf 'Built app not found: %s\n' "$app_path" >&2
  exit 1
fi

identity="${SHORTY_CODESIGN_IDENTITY:--}"
app_entitlements="$REPO_ROOT/app/Shorty/Shorty.entitlements"
extension_entitlements="$REPO_ROOT/app/Shorty/ShortySafariWebExtension.entitlements"

signing_args=(--force --sign "$identity")
if [ "$identity" = "-" ]; then
  printf 'Signing %s with ad-hoc identity for local packaging.\n' "$app_path"
else
  printf 'Signing %s with identity %s.\n' "$app_path" "$identity"
  signing_args+=(--options runtime --timestamp)
fi

sign_path() {
  local path="$1"
  shift
  codesign "${signing_args[@]}" "$@" "$path"
}

if [ -d "$app_path/Contents/Frameworks" ]; then
  while IFS= read -r -d '' framework_path; do
    sign_path "$framework_path"
  done < <(find "$app_path/Contents/Frameworks" -maxdepth 1 -name '*.framework' -print0)

  while IFS= read -r -d '' dylib_path; do
    sign_path "$dylib_path"
  done < <(find "$app_path/Contents/Frameworks" -maxdepth 1 -name '*.dylib' -print0)
fi

if [ -d "$app_path/Contents/PlugIns" ]; then
  while IFS= read -r -d '' extension_path; do
    sign_path "$extension_path" --entitlements "$extension_entitlements"
  done < <(find "$app_path/Contents/PlugIns" -maxdepth 1 -name '*.appex' -print0)
fi

sign_path "$app_path" --entitlements "$app_entitlements"

codesign --verify --deep --strict --verbose=2 "$app_path"

package_args=(
  --version "$version"
  --app-path "$app_path"
  --output-dir "$REPO_ROOT/.build/releases"
)
if [ -n "$artifact_label" ]; then
  package_args+=(--artifact-label "$artifact_label")
fi

uv run python -m scripts.tooling.package_app "${package_args[@]}"

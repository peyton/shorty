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
if [ "$identity" = "-" ]; then
  printf 'Signing %s with ad-hoc identity for local packaging.\n' "$app_path"
  codesign --force --deep --sign - "$app_path"
else
  printf 'Signing %s with identity %s.\n' "$app_path" "$identity"
  codesign --force --deep --options runtime --timestamp --sign "$identity" "$app_path"
fi

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

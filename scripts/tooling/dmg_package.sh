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
  printf 'Usage: just dmg-package VERSION=<version>\n' >&2
  exit 2
fi

app_path="$REPO_ROOT/$BUILD_DERIVED_DATA/Build/Products/Release/$APP_PRODUCT_NAME.app"
if [ ! -d "$app_path" ]; then
  "$TOOLING_DIR/app_package.sh" --version "$version"
fi

release_dir="$REPO_ROOT/.build/releases"
staging_dir="$REPO_ROOT/.build/dmg/shorty-$version"
dmg_path="$release_dir/shorty-$version-macos.dmg"
checksum_path="$dmg_path.sha256"

rm -rf "$staging_dir" "$dmg_path"
mkdir -p "$staging_dir" "$release_dir"
ditto "$app_path" "$staging_dir/$APP_PRODUCT_NAME.app"
ln -s /Applications "$staging_dir/Applications"

hdiutil create \
  -volname "Shorty $version" \
  -srcfolder "$staging_dir" \
  -ov \
  -format UDZO \
  "$dmg_path"

shasum -a 256 "$dmg_path" | sed "s#  $dmg_path#  $(basename "$dmg_path")#" >"$checksum_path"
printf 'Created %s\n' "$dmg_path"
printf 'Created %s\n' "$checksum_path"

#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(cd -- "$(dirname -- "$0")" && pwd)/common.sh"

setup_local_tooling_env

"$TOOLING_DIR/build.sh" \
  --configuration Debug \
  --derived-data-path "$REPO_ROOT/$RUN_DERIVED_DATA"

app_path="$REPO_ROOT/$RUN_DERIVED_DATA/Build/Products/Debug/$APP_PRODUCT_NAME.app"
if [ ! -d "$app_path" ]; then
  printf 'Built app not found: %s\n' "$app_path" >&2
  exit 1
fi

open "$app_path"

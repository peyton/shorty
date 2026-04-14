#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(cd -- "$(dirname -- "$0")" && pwd)/common.sh"

setup_local_tooling_env

profile="${1:-idle}"
duration="${SHORTY_PROFILE_DURATION:-30s}"
output="$REPO_ROOT/.build/profiles/shorty-$profile.trace"
mkdir -p "$(dirname "$output")"

printf 'Recording Shorty %s profile for %s...\n' "$profile" "$duration"
xcrun xctrace record \
  --template "Time Profiler" \
  --time-limit "$duration" \
  --output "$output" \
  --attach "$APP_PRODUCT_NAME"

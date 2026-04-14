#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(cd -- "$(dirname -- "$0")" && pwd)/common.sh"

setup_local_tooling_env

version=""
build_number=""

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
  *)
    printf 'Unknown argument: %s\n' "$1" >&2
    exit 2
    ;;
  esac
done

args=()
if [ -n "$version" ]; then
  args+=(--version "$version")
fi
if [ -n "$build_number" ]; then
  args+=(--build-number "$build_number")
fi

uv run python -m scripts.tooling.app_store_validate "${args[@]}"

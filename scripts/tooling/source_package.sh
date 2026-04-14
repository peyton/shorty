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
  printf 'Usage: just source-package VERSION=<version>\n' >&2
  exit 2
fi

uv run python -m scripts.tooling.source_package \
  --version "$version" \
  --output-dir "$REPO_ROOT/.build/releases"

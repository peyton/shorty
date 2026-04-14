#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(cd -- "$(dirname -- "$0")" && pwd)/common.sh"

setup_local_tooling_env

version=""
download_url="${SHORTY_RELEASE_DOWNLOAD_URL:-}"
allow_unsigned=0

while [ $# -gt 0 ]; do
  case "$1" in
  --version)
    version="$2"
    shift 2
    ;;
  --download-url)
    download_url="$2"
    shift 2
    ;;
  --allow-unsigned)
    allow_unsigned=1
    shift
    ;;
  *)
    printf 'Unknown argument: %s\n' "$1" >&2
    exit 2
    ;;
  esac
done

if [ -z "$version" ] || [ -z "$download_url" ]; then
  printf 'Usage: just appcast-generate VERSION=<version> DOWNLOAD_URL=<url>\n' >&2
  exit 2
fi

args=(--version "$version" --download-url "$download_url")
if [ "$allow_unsigned" -eq 1 ]; then
  args+=(--allow-unsigned)
fi

uv run python -m scripts.tooling.appcast_generate "${args[@]}"

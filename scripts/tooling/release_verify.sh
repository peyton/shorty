#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(cd -- "$(dirname -- "$0")" && pwd)/common.sh"

setup_local_tooling_env

version=""
artifact_label=""
require_codesign=0
require_gatekeeper=0
require_staple=0

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
  --require-codesign)
    require_codesign=1
    shift
    ;;
  --require-gatekeeper)
    require_gatekeeper=1
    shift
    ;;
  --require-staple)
    require_staple=1
    shift
    ;;
  *)
    printf 'Unknown argument: %s\n' "$1" >&2
    exit 2
    ;;
  esac
done

if [ -z "$version" ]; then
  printf 'Usage: just release-verify VERSION=<version> [ARTIFACT_LABEL=<label>]\n' >&2
  exit 2
fi

args=(--version "$version")
if [ -n "$artifact_label" ]; then
  args+=(--artifact-label "$artifact_label")
fi
if [ "$require_codesign" -eq 1 ]; then
  args+=(--require-codesign)
fi
if [ "$require_gatekeeper" -eq 1 ]; then
  args+=(--require-gatekeeper)
fi
if [ "$require_staple" -eq 1 ]; then
  args+=(--require-staple)
fi

uv run python -m scripts.tooling.release_verify "${args[@]}"

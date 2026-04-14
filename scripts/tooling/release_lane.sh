#!/usr/bin/env bash
set -euo pipefail

version=""
lane="developer-id-with-safari"

while [ $# -gt 0 ]; do
  case "$1" in
  --version)
    version="$2"
    shift 2
    ;;
  --lane)
    lane="$2"
    shift 2
    ;;
  *)
    printf 'Unknown argument: %s\n' "$1" >&2
    exit 2
    ;;
  esac
done

if [ -z "$version" ]; then
  printf 'Usage: just release VERSION=<version> [LANE=<lane>]\n' >&2
  exit 2
fi

case "$lane" in
developer-id)
  just build
  just release-preflight VERSION="$version"
  just app-package VERSION="$version"
  just app-notarize VERSION="$version"
  just dmg-package VERSION="$version"
  bash scripts/tooling/release_verify.sh \
    --version "$version" \
    --require-codesign \
    --require-gatekeeper \
    --require-staple
  ;;
developer-id-with-safari)
  just build
  just release-preflight VERSION="$version"
  just app-package VERSION="$version"
  just app-notarize VERSION="$version"
  just safari-extension-verify
  just dmg-package VERSION="$version"
  bash scripts/tooling/release_verify.sh \
    --version "$version" \
    --require-codesign \
    --require-gatekeeper \
    --require-staple
  ;;
app-store-candidate)
  just app-store-build
  just app-store-validate
  ;;
*)
  printf 'Unknown release lane: %s\n' "$lane" >&2
  exit 2
  ;;
esac

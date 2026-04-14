#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

typecheck_dir=".build/typecheck"
rm -rf "$typecheck_dir"
mkdir -p "$typecheck_dir"

core_sources=()
while IFS= read -r source; do core_sources+=("$source"); done < <(
  find app/Shorty/Sources/ShortyCore -name '*.swift' | sort
)
app_sources=()
while IFS= read -r source; do app_sources+=("$source"); done < <(
  find app/Shorty/Sources/Shorty -name '*.swift' | sort
)
app_view_sources=()
while IFS= read -r source; do app_view_sources+=("$source"); done < <(
  find app/Shorty/Sources/Shorty -name '*.swift' ! -name 'ShortyApp.swift' | sort
)
bridge_sources=()
while IFS= read -r source; do bridge_sources+=("$source"); done < <(
  find app/Shorty/Sources/ShortyBridge -name '*.swift' | sort
)
screenshot_sources=()
while IFS= read -r source; do screenshot_sources+=("$source"); done < <(
  find app/Shorty/Sources/ShortyScreenshots -name '*.swift' | sort
)

xcrun swiftc \
  -emit-module \
  -parse-as-library \
  -target arm64-apple-macos13.0 \
  -module-name ShortyCore \
  -emit-module-path "$typecheck_dir/ShortyCore.swiftmodule" \
  "${core_sources[@]}"

xcrun swiftc \
  -typecheck \
  -target arm64-apple-macos13.0 \
  -parse-as-library \
  -I "$typecheck_dir" \
  "${app_sources[@]}"

xcrun swiftc \
  -typecheck \
  -target arm64-apple-macos13.0 \
  -I "$typecheck_dir" \
  "${bridge_sources[@]}"

xcrun swiftc \
  -typecheck \
  -target arm64-apple-macos13.0 \
  -I "$typecheck_dir" \
  "${app_view_sources[@]}" \
  "${screenshot_sources[@]}"

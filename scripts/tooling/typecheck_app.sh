#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

typecheck_dir=".build/typecheck"
rm -rf "$typecheck_dir"
mkdir -p "$typecheck_dir"

developer_dir="$(xcode-select -p)"
test_framework_search_path="$developer_dir/Platforms/MacOSX.platform/Developer/Library/Frameworks"
test_library_search_path="$developer_dir/Platforms/MacOSX.platform/Developer/usr/lib"
test_import_flags=(
  -F "$test_framework_search_path"
  -I "$test_library_search_path"
  -L "$test_library_search_path"
)

core_sources=()
while IFS= read -r source; do core_sources+=("$source"); done < <(
  find app/Shorty/Sources/ShortyCore -name '*.swift' | sort
)
core_test_sources=()
while IFS= read -r source; do core_test_sources+=("$source"); done < <(
  find app/Shorty/Tests/ShortyCoreTests -name '*.swift' | sort
)
app_sources=()
while IFS= read -r source; do app_sources+=("$source"); done < <(
  find app/Shorty/Sources/Shorty -name '*.swift' | sort
)
app_view_sources=()
while IFS= read -r source; do app_view_sources+=("$source"); done < <(
  find app/Shorty/Sources/Shorty -name '*.swift' ! -name 'ShortyApp.swift' | sort
)
app_test_sources=()
while IFS= read -r source; do app_test_sources+=("$source"); done < <(
  find app/Shorty/Tests/ShortyTests -name '*.swift' | sort
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
  -enable-testing \
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
  -emit-module \
  -parse-as-library \
  -enable-testing \
  -target arm64-apple-macos13.0 \
  -module-name Shorty \
  -emit-module-path "$typecheck_dir/Shorty.swiftmodule" \
  -I "$typecheck_dir" \
  "${app_sources[@]}"

xcrun swiftc \
  -typecheck \
  -target arm64-apple-macos13.0 \
  -parse-as-library \
  -I "$typecheck_dir" \
  "${test_import_flags[@]}" \
  "${core_test_sources[@]}"

xcrun swiftc \
  -typecheck \
  -target arm64-apple-macos13.0 \
  -parse-as-library \
  -I "$typecheck_dir" \
  "${test_import_flags[@]}" \
  "${app_test_sources[@]}"

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

#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(cd -- "$(dirname -- "$0")" && pwd)/common.sh"

setup_local_tooling_env

version=""
build_number=""
archive_path=""
export_path=""

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
  --archive-path)
    archive_path="$2"
    shift 2
    ;;
  --export-path)
    export_path="$2"
    shift 2
    ;;
  *)
    printf 'Unknown argument: %s\n' "$1" >&2
    exit 2
    ;;
  esac
done

if [ -z "$version" ] || [ -z "$build_number" ]; then
  printf 'Usage: just app-store-export-testflight VERSION=<version> BUILD_NUMBER=<number>\n' >&2
  exit 2
fi

validate_app_version "$version"
validate_apple_build_number "$build_number"
require_app_store_connect_credentials

if [ -z "$archive_path" ]; then
  archive_path="$REPO_ROOT/.build/app-store/ShortyAppStore-$version-$build_number.xcarchive"
fi
if [ -z "$export_path" ]; then
  export_path="$REPO_ROOT/.build/app-store/testflight-upload-$version-$build_number"
fi

if [ ! -d "$archive_path" ]; then
  "$TOOLING_DIR/app_store_archive.sh" \
    --version "$version" \
    --build-number "$build_number" \
    --archive-path "$archive_path"
fi

export_options="$REPO_ROOT/.build/app-store/export-options-testflight.plist"
mkdir -p "$(dirname "$export_options")" "$export_path"
cat >"$export_options" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>export</string>
  <key>manageAppVersionAndBuildNumber</key>
  <false/>
  <key>method</key>
  <string>app-store-connect</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>${TEAM_ID}</string>
  <key>testFlightInternalTestingOnly</key>
  <true/>
  <key>uploadSymbols</key>
  <true/>
</dict>
</plist>
EOF

auth_args=(
  -authenticationKeyPath "$SHORTY_APP_STORE_CONNECT_KEY_PATH"
  -authenticationKeyID "$SHORTY_APP_STORE_CONNECT_KEY_ID"
  -authenticationKeyIssuerID "$SHORTY_APP_STORE_CONNECT_ISSUER_ID"
)

xcodebuild \
  -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$export_path" \
  -exportOptionsPlist "$export_options" \
  -allowProvisioningUpdates \
  "${auth_args[@]}"

upload_package="$(find "$export_path" -type f \( -name '*.pkg' -o -name '*.ipa' \) -print -quit)"
if [ -z "$upload_package" ]; then
  printf 'No App Store package (.pkg or .ipa) was exported to %s\n' "$export_path" >&2
  exit 1
fi

if xcrun --find altool >/dev/null 2>&1; then
  upload_log="$(mktemp "${TMPDIR:-/tmp}/shorty-altool.XXXXXX.log")"
  trap 'rm -f "$upload_log"' EXIT

  set +e
  xcrun altool \
    --upload-package "$upload_package" \
    --api-key "$SHORTY_APP_STORE_CONNECT_KEY_ID" \
    --api-issuer "$SHORTY_APP_STORE_CONNECT_ISSUER_ID" \
    --p8-file-path "$SHORTY_APP_STORE_CONNECT_KEY_PATH" \
    --show-progress \
    --wait \
    --output-format normal 2>&1 | tee "$upload_log"
  altool_status=${PIPESTATUS[0]}
  set -e

  if [ "$altool_status" -ne 0 ] ||
    grep -Eq '(^|[[:space:]])ERROR:|UPLOAD FAILED|Validation failed \([0-9]+\)|STATE_ERROR\.' "$upload_log"; then
    printf 'App Store Connect upload failed for %s\n' "$upload_package" >&2
    exit 1
  fi
else
  transporter_tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/shorty-transporter.XXXXXX")"
  trap 'rm -rf "$transporter_tmp_dir"' EXIT

  mkdir -p "$transporter_tmp_dir/private_keys"
  cp "$SHORTY_APP_STORE_CONNECT_KEY_PATH" \
    "$transporter_tmp_dir/private_keys/AuthKey_${SHORTY_APP_STORE_CONNECT_KEY_ID}.p8"

  (
    cd "$transporter_tmp_dir"
    xcrun iTMSTransporter \
      -m upload \
      -assetFile "$upload_package" \
      -apiKey "$SHORTY_APP_STORE_CONNECT_KEY_ID" \
      -apiIssuer "$SHORTY_APP_STORE_CONNECT_ISSUER_ID" \
      -apiKeyType team \
      -v informational
  )
fi

printf 'Submitted TestFlight upload package %s from archive %s\n' "$upload_package" "$archive_path"

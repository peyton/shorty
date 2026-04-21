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

app_bundle_path="$archive_path/Products/Applications/ShortyAppStore.app"
extension_bundle_path="$app_bundle_path/Contents/PlugIns/ShortyAppStoreSafariWebExtension.appex"
app_profile_path="$app_bundle_path/Contents/embedded.provisionprofile"
extension_profile_path="$extension_bundle_path/Contents/embedded.provisionprofile"

if [ ! -f "$app_profile_path" ]; then
  printf 'Embedded app provisioning profile missing from archive: %s\n' "$app_profile_path" >&2
  exit 1
fi
if [ ! -f "$extension_profile_path" ]; then
  printf 'Embedded extension provisioning profile missing from archive: %s\n' "$extension_profile_path" >&2
  exit 1
fi

extract_profile_value() {
  local profile_path="$1"
  local key_path="$2"
  local profile_plist
  profile_plist="$(mktemp "${TMPDIR:-/tmp}/shorty-profile.XXXXXX.plist")"
  security cms -D -i "$profile_path" >"$profile_plist"
  /usr/libexec/PlistBuddy -c "Print :$key_path" "$profile_plist"
  rm -f "$profile_plist"
}

app_profile_uuid="$(extract_profile_value "$app_profile_path" "UUID")"
app_profile_name="$(extract_profile_value "$app_profile_path" "Name")"
extension_profile_uuid="$(extract_profile_value "$extension_profile_path" "UUID")"
extension_profile_name="$(extract_profile_value "$extension_profile_path" "Name")"

local_profiles_dir="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$local_profiles_dir"
cp "$app_profile_path" "$local_profiles_dir/$app_profile_uuid.provisionprofile"
cp "$extension_profile_path" "$local_profiles_dir/$extension_profile_uuid.provisionprofile"

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
  <string>manual</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>app.peyton.shorty.appstore</key>
    <string>${app_profile_name}</string>
    <key>app.peyton.shorty.appstore.SafariWebExtension</key>
    <string>${extension_profile_name}</string>
  </dict>
  <key>teamID</key>
  <string>${TEAM_ID}</string>
  <key>testFlightInternalTestingOnly</key>
  <true/>
  <key>uploadSymbols</key>
  <true/>
</dict>
</plist>
EOF

xcodebuild \
  -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$export_path" \
  -exportOptionsPlist "$export_options"

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

#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(cd -- "$(dirname -- "$0")" && pwd)/common.sh"

if [ -z "${RUNNER_TEMP:-}" ] || [ -z "${GITHUB_ENV:-}" ]; then
  printf 'import_ci_release_secrets.sh must run inside GitHub Actions.\n' >&2
  exit 2
fi

require_secret() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    printf '::error title=Missing release secret::%s is required.\n' "$name" >&2
    return 1
  fi
}

write_secret_file() {
  local value="$1"
  local destination="$2"
  (
    umask 077
    printf '%s\n' "$value" >"$destination"
  )
}

decode_base64_secret_file() {
  local value="$1"
  local destination="$2"
  (
    umask 077
    if printf '%s' "$value" | base64 --decode >"$destination" 2>/dev/null; then
      return 0
    fi
    if printf '%s' "$value" | base64 -d >"$destination" 2>/dev/null; then
      return 0
    fi
    if printf '%s' "$value" | base64 -D >"$destination" 2>/dev/null; then
      return 0
    fi
    return 1
  )
}

write_profile_file() {
  local value="$1"
  local destination="$2"
  local secret_name="$3"
  local decoded_path="$destination.decoded"

  if decode_base64_secret_file "$value" "$decoded_path" &&
    security cms -D -i "$decoded_path" >/dev/null 2>&1; then
    mv "$decoded_path" "$destination"
    chmod 644 "$destination"
    return 0
  fi
  rm -f "$decoded_path"

  write_secret_file "$value" "$destination"
  if security cms -D -i "$destination" >/dev/null 2>&1; then
    chmod 644 "$destination"
    return 0
  fi

  printf '::error title=Invalid provisioning profile secret::%s must contain a valid provisioning profile (prefer base64 profileContent from App Store Connect).\n' "$secret_name" >&2
  return 1
}

write_github_env() {
  local name="$1"
  local value="$2"
  printf '%s=%s\n' "$name" "$value" >>"$GITHUB_ENV"
}

missing=0
for name in \
  SHORTY_DEVELOPER_ID_CERTIFICATE_PEM \
  SHORTY_DEVELOPER_ID_APP_PROFILE \
  SHORTY_DEVELOPER_ID_EXTENSION_PROFILE \
  SHORTY_APP_STORE_APP_PROFILE \
  SHORTY_APP_STORE_EXTENSION_PROFILE \
  SHORTY_DEVELOPER_ID_PRIVATE_KEY_PEM \
  SHORTY_CI_KEYCHAIN_PASSWORD \
  SHORTY_CODESIGN_IDENTITY \
  SHORTY_APP_STORE_CONNECT_API_KEY_P8 \
  SHORTY_APP_STORE_CONNECT_KEY_ID \
  SHORTY_APP_STORE_CONNECT_ISSUER_ID; do
  require_secret "$name" || missing=1
done
if [ "$missing" -ne 0 ]; then
  exit 2
fi

certificate_path="$RUNNER_TEMP/shorty-developer-id-certificate.pem"
private_key_path="$RUNNER_TEMP/shorty-developer-id-private-key.pem"
keychain_path="$RUNNER_TEMP/shorty-signing.keychain-db"
app_store_key_path="$RUNNER_TEMP/AuthKey_${SHORTY_APP_STORE_CONNECT_KEY_ID}.p8"
app_profile_path="$RUNNER_TEMP/shorty-developer-id-app.provisionprofile"
extension_profile_path="$RUNNER_TEMP/shorty-developer-id-extension.provisionprofile"
app_store_app_profile_path="$RUNNER_TEMP/shorty-app-store-app.provisionprofile"
app_store_extension_profile_path="$RUNNER_TEMP/shorty-app-store-extension.provisionprofile"

write_secret_file "$SHORTY_DEVELOPER_ID_CERTIFICATE_PEM" "$certificate_path"
write_secret_file "$SHORTY_DEVELOPER_ID_PRIVATE_KEY_PEM" "$private_key_path"
write_secret_file "$SHORTY_APP_STORE_CONNECT_API_KEY_P8" "$app_store_key_path"

security create-keychain -p "$SHORTY_CI_KEYCHAIN_PASSWORD" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$SHORTY_CI_KEYCHAIN_PASSWORD" "$keychain_path"
identity_bundle_path="$RUNNER_TEMP/shorty-developer-id-identity.p12"
openssl_pkcs12_args=(
  pkcs12
  -export
  -inkey "$private_key_path"
  -in "$certificate_path"
  -out "$identity_bundle_path"
  -passout "pass:$SHORTY_CI_KEYCHAIN_PASSWORD"
)
if [ -n "${SHORTY_DEVELOPER_ID_PRIVATE_KEY_PASSWORD:-}" ]; then
  openssl_pkcs12_args+=(-passin "pass:$SHORTY_DEVELOPER_ID_PRIVATE_KEY_PASSWORD")
fi
openssl "${openssl_pkcs12_args[@]}"
security import "$identity_bundle_path" \
  -A \
  -P "$SHORTY_CI_KEYCHAIN_PASSWORD" \
  -f pkcs12 \
  -k "$keychain_path"

security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s \
  -k "$SHORTY_CI_KEYCHAIN_PASSWORD" \
  "$keychain_path"
security list-keychains -d user -s "$keychain_path"

if ! security find-identity -v -p codesigning "$keychain_path" | grep -Fq "$SHORTY_CODESIGN_IDENTITY"; then
  printf '::error title=Missing Developer ID identity::Imported keychain does not contain %s.\n' "$SHORTY_CODESIGN_IDENTITY" >&2
  security find-identity -v -p codesigning "$keychain_path" >&2 || true
  exit 1
fi

write_github_env SHORTY_APP_STORE_CONNECT_KEY_PATH "$app_store_key_path"
write_github_env SHORTY_APP_STORE_CONNECT_KEY_ID "$SHORTY_APP_STORE_CONNECT_KEY_ID"
write_github_env SHORTY_APP_STORE_CONNECT_ISSUER_ID "$SHORTY_APP_STORE_CONNECT_ISSUER_ID"
write_github_env SHORTY_CODESIGN_IDENTITY "$SHORTY_CODESIGN_IDENTITY"
write_github_env SHORTY_DEVELOPER_ID_KEYCHAIN_PATH "$keychain_path"

write_profile_file "$SHORTY_DEVELOPER_ID_APP_PROFILE" "$app_profile_path" SHORTY_DEVELOPER_ID_APP_PROFILE
write_github_env SHORTY_DEVELOPER_ID_APP_PROFILE_PATH "$app_profile_path"
write_profile_file "$SHORTY_DEVELOPER_ID_EXTENSION_PROFILE" "$extension_profile_path" SHORTY_DEVELOPER_ID_EXTENSION_PROFILE
write_github_env SHORTY_DEVELOPER_ID_EXTENSION_PROFILE_PATH "$extension_profile_path"
write_profile_file "$SHORTY_APP_STORE_APP_PROFILE" "$app_store_app_profile_path" SHORTY_APP_STORE_APP_PROFILE
write_github_env SHORTY_APP_STORE_APP_PROFILE_PATH "$app_store_app_profile_path"
write_profile_file "$SHORTY_APP_STORE_EXTENSION_PROFILE" "$app_store_extension_profile_path" SHORTY_APP_STORE_EXTENSION_PROFILE
write_github_env SHORTY_APP_STORE_EXTENSION_PROFILE_PATH "$app_store_extension_profile_path"

printf 'Imported Developer ID signing identity and App Store Connect key.\n'

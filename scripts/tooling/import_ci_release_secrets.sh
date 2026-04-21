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

any_secret_present() {
  local name=""
  for name in "$@"; do
    if [ -n "${!name:-}" ]; then
      return 0
    fi
  done
  return 1
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
  local compact_value=""
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
    compact_value="$(printf '%s' "$value" | tr -d '[:space:]')"
    if [ -n "$compact_value" ] &&
      printf '%s' "$compact_value" | base64 --decode >"$destination" 2>/dev/null; then
      return 0
    fi
    if [ -n "$compact_value" ] &&
      printf '%s' "$compact_value" | base64 -d >"$destination" 2>/dev/null; then
      return 0
    fi
    if [ -n "$compact_value" ] &&
      printf '%s' "$compact_value" | base64 -D >"$destination" 2>/dev/null; then
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
    provisioning_profile_is_valid "$decoded_path"; then
    mv "$decoded_path" "$destination"
    chmod 644 "$destination"
    return 0
  fi
  rm -f "$decoded_path"

  write_secret_file "$value" "$destination"
  if provisioning_profile_is_valid "$destination"; then
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

validate_certificate_subject() {
  local certificate_path="$1"
  local expected_label="$2"
  local secret_name="$3"
  local subject=""

  subject="$(openssl x509 -in "$certificate_path" -noout -subject 2>/dev/null || true)"
  if [[ "$subject" == *"$expected_label"* ]]; then
    return 0
  fi

  printf '::error title=Unexpected certificate subject::%s must contain a %s certificate.\n' \
    "$secret_name" \
    "$expected_label" >&2
  return 1
}

import_pem_identity() {
  local certificate_path="$1"
  local private_key_path="$2"
  local private_key_password="$3"
  local identity_bundle_path="$4"
  local keychain_path="$5"
  local -a openssl_pkcs12_args=(
    pkcs12
    -export
    -inkey "$private_key_path"
    -in "$certificate_path"
    -out "$identity_bundle_path"
    -passout "pass:$SHORTY_CI_KEYCHAIN_PASSWORD"
  )

  if [ -n "$private_key_password" ]; then
    openssl_pkcs12_args+=(-passin "pass:$private_key_password")
  fi

  openssl "${openssl_pkcs12_args[@]}"
  security import "$identity_bundle_path" \
    -A \
    -P "$SHORTY_CI_KEYCHAIN_PASSWORD" \
    -f pkcs12 \
    -k "$keychain_path"
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

app_store_signing_secrets_present=0
if any_secret_present \
  SHORTY_APPLE_DISTRIBUTION_CERTIFICATE_PEM \
  SHORTY_APPLE_DISTRIBUTION_PRIVATE_KEY_PEM \
  SHORTY_APPLE_DISTRIBUTION_PRIVATE_KEY_PASSWORD \
  SHORTY_MAC_INSTALLER_DISTRIBUTION_CERTIFICATE_PEM \
  SHORTY_MAC_INSTALLER_DISTRIBUTION_PRIVATE_KEY_PEM \
  SHORTY_MAC_INSTALLER_DISTRIBUTION_PRIVATE_KEY_PASSWORD; then
  app_store_signing_secrets_present=1
  for name in \
    SHORTY_APPLE_DISTRIBUTION_CERTIFICATE_PEM \
    SHORTY_APPLE_DISTRIBUTION_PRIVATE_KEY_PEM \
    SHORTY_MAC_INSTALLER_DISTRIBUTION_CERTIFICATE_PEM \
    SHORTY_MAC_INSTALLER_DISTRIBUTION_PRIVATE_KEY_PEM; do
    require_secret "$name" || missing=1
  done
fi

if [ "$missing" -ne 0 ]; then
  exit 2
fi

certificate_path="$RUNNER_TEMP/shorty-developer-id-certificate.pem"
private_key_path="$RUNNER_TEMP/shorty-developer-id-private-key.pem"
apple_distribution_certificate_path="$RUNNER_TEMP/shorty-apple-distribution-certificate.pem"
apple_distribution_private_key_path="$RUNNER_TEMP/shorty-apple-distribution-private-key.pem"
mac_installer_certificate_path="$RUNNER_TEMP/shorty-mac-installer-distribution-certificate.pem"
mac_installer_private_key_path="$RUNNER_TEMP/shorty-mac-installer-distribution-private-key.pem"
keychain_path="$RUNNER_TEMP/shorty-signing.keychain-db"
app_store_key_path="$RUNNER_TEMP/AuthKey_${SHORTY_APP_STORE_CONNECT_KEY_ID}.p8"
app_profile_path="$RUNNER_TEMP/shorty-developer-id-app.provisionprofile"
extension_profile_path="$RUNNER_TEMP/shorty-developer-id-extension.provisionprofile"
app_store_app_profile_path="$RUNNER_TEMP/shorty-app-store-app.provisionprofile"
app_store_extension_profile_path="$RUNNER_TEMP/shorty-app-store-extension.provisionprofile"

write_secret_file "$SHORTY_DEVELOPER_ID_CERTIFICATE_PEM" "$certificate_path"
write_secret_file "$SHORTY_DEVELOPER_ID_PRIVATE_KEY_PEM" "$private_key_path"
write_secret_file "$SHORTY_APP_STORE_CONNECT_API_KEY_P8" "$app_store_key_path"
if [ "$app_store_signing_secrets_present" -eq 1 ]; then
  write_secret_file "$SHORTY_APPLE_DISTRIBUTION_CERTIFICATE_PEM" \
    "$apple_distribution_certificate_path"
  write_secret_file "$SHORTY_APPLE_DISTRIBUTION_PRIVATE_KEY_PEM" \
    "$apple_distribution_private_key_path"
  write_secret_file "$SHORTY_MAC_INSTALLER_DISTRIBUTION_CERTIFICATE_PEM" \
    "$mac_installer_certificate_path"
  write_secret_file "$SHORTY_MAC_INSTALLER_DISTRIBUTION_PRIVATE_KEY_PEM" \
    "$mac_installer_private_key_path"
fi

security create-keychain -p "$SHORTY_CI_KEYCHAIN_PASSWORD" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$SHORTY_CI_KEYCHAIN_PASSWORD" "$keychain_path"

import_pem_identity \
  "$certificate_path" \
  "$private_key_path" \
  "${SHORTY_DEVELOPER_ID_PRIVATE_KEY_PASSWORD:-}" \
  "$RUNNER_TEMP/shorty-developer-id-identity.p12" \
  "$keychain_path"

if [ "$app_store_signing_secrets_present" -eq 1 ]; then
  validate_certificate_subject \
    "$apple_distribution_certificate_path" \
    "Apple Distribution" \
    SHORTY_APPLE_DISTRIBUTION_CERTIFICATE_PEM
  validate_certificate_subject \
    "$mac_installer_certificate_path" \
    "Mac Installer Distribution" \
    SHORTY_MAC_INSTALLER_DISTRIBUTION_CERTIFICATE_PEM

  import_pem_identity \
    "$apple_distribution_certificate_path" \
    "$apple_distribution_private_key_path" \
    "${SHORTY_APPLE_DISTRIBUTION_PRIVATE_KEY_PASSWORD:-}" \
    "$RUNNER_TEMP/shorty-apple-distribution-identity.p12" \
    "$keychain_path"
  import_pem_identity \
    "$mac_installer_certificate_path" \
    "$mac_installer_private_key_path" \
    "${SHORTY_MAC_INSTALLER_DISTRIBUTION_PRIVATE_KEY_PASSWORD:-}" \
    "$RUNNER_TEMP/shorty-mac-installer-distribution-identity.p12" \
    "$keychain_path"
fi

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

if [ "$app_store_signing_secrets_present" -eq 1 ] &&
  ! security find-identity -v -p codesigning "$keychain_path" | grep -Fq "Apple Distribution"; then
  printf '::error title=Missing Apple Distribution identity::Imported keychain does not contain an Apple Distribution signing identity.\n' >&2
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

if [ "$app_store_signing_secrets_present" -eq 1 ]; then
  write_github_env SHORTY_APP_STORE_ALLOW_LOCAL_SIGNING 1
  write_github_env SHORTY_APP_STORE_PREFER_MANUAL_PROFILES 1
  printf 'Imported Developer ID signing identity, App Store signing identities, and App Store Connect key.\n'
else
  printf 'Imported Developer ID signing identity and App Store Connect key.\n'
fi

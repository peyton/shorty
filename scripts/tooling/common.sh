#!/usr/bin/env bash
set -euo pipefail

TOOLING_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$TOOLING_DIR/../.." && pwd)"

set -a
# shellcheck source=/dev/null
source "$TOOLING_DIR/shorty.env"
set +a

ensure_local_state() {
  mkdir -p \
    "$REPO_ROOT/.build" \
    "$REPO_ROOT/.cache/hk" \
    "$REPO_ROOT/.cache/npm" \
    "$REPO_ROOT/.cache/swiftlint" \
    "$REPO_ROOT/.cache/uv" \
    "$REPO_ROOT/.config" \
    "$REPO_ROOT/.config/mise" \
    "$REPO_ROOT/.state/hk"
}

setup_local_tooling_env() {
  ensure_local_state

  export MISE_CONFIG_DIR="$REPO_ROOT/.config/mise"
  export UV_CACHE_DIR="$REPO_ROOT/.cache/uv"
  export UV_PROJECT_ENVIRONMENT="$REPO_ROOT/.venv"
  export HK_CACHE_DIR="$REPO_ROOT/.cache/hk"
  export HK_STATE_DIR="$REPO_ROOT/.state/hk"
  export npm_config_cache="$REPO_ROOT/.cache/npm"
  export TUIST_TEAM_ID="${TEAM_ID:-}"
  sync_tuist_shorty_version_env
}

sync_tuist_shorty_version_env() {
  if [ -n "${SHORTY_MARKETING_VERSION:-}" ]; then
    export TUIST_SHORTY_MARKETING_VERSION="$SHORTY_MARKETING_VERSION"
  else
    unset TUIST_SHORTY_MARKETING_VERSION
  fi
  if [ -n "${SHORTY_BUILD_NUMBER:-}" ]; then
    export TUIST_SHORTY_BUILD_NUMBER="$SHORTY_BUILD_NUMBER"
  else
    unset TUIST_SHORTY_BUILD_NUMBER
  fi
}

run_mise() {
  command mise trust "$REPO_ROOT/mise.toml" >/dev/null 2>&1 || true
  mise "$@"
}

run_mise_exec() {
  run_mise exec -- "$@"
}

run_in_app() {
  (
    cd "$REPO_ROOT/app"
    "$@"
  )
}

repo_app_version() {
  tr -d '[:space:]' <"$REPO_ROOT/VERSION"
}

validate_app_version() {
  uv run python -m scripts.tooling.versioning app-version --version "$1" >/dev/null
}

validate_apple_build_number() {
  uv run python -m scripts.tooling.versioning build-number --build-number "$1" >/dev/null
}

app_store_connect_auth_args() {
  local key_path="${SHORTY_APP_STORE_CONNECT_KEY_PATH:-}"
  local key_id="${SHORTY_APP_STORE_CONNECT_KEY_ID:-}"
  local issuer_id="${SHORTY_APP_STORE_CONNECT_ISSUER_ID:-}"

  if [ -z "$key_path" ] || [ -z "$key_id" ] || [ -z "$issuer_id" ]; then
    return 1
  fi
  if [ ! -f "$key_path" ]; then
    printf 'App Store Connect API key file not found: %s\n' "$key_path" >&2
    return 1
  fi

  printf '%s\n' \
    -authenticationKeyPath "$key_path" \
    -authenticationKeyID "$key_id" \
    -authenticationKeyIssuerID "$issuer_id"
}

require_app_store_archive_signing() {
  if [ "${SHORTY_APP_STORE_ALLOW_LOCAL_SIGNING:-}" = "1" ]; then
    return 0
  fi
  if app_store_connect_auth_args >/dev/null; then
    return 0
  fi

  cat >&2 <<'EOF'
App Store archive requires explicit signing credentials.
Set SHORTY_APP_STORE_ALLOW_LOCAL_SIGNING=1 to use installed Apple distribution
certificates/profiles, or set SHORTY_APP_STORE_CONNECT_KEY_PATH,
SHORTY_APP_STORE_CONNECT_KEY_ID, and SHORTY_APP_STORE_CONNECT_ISSUER_ID.
EOF
  return 1
}

require_app_store_connect_credentials() {
  if app_store_connect_auth_args >/dev/null; then
    return 0
  fi

  cat >&2 <<'EOF'
TestFlight upload requires App Store Connect API credentials:
SHORTY_APP_STORE_CONNECT_KEY_PATH, SHORTY_APP_STORE_CONNECT_KEY_ID, and
SHORTY_APP_STORE_CONNECT_ISSUER_ID.
EOF
  return 1
}

generate_workspace() {
  run_in_app run_mise_exec tuist generate --no-open --no-binary-cache --cache-profile none
}

workspace_is_generated() {
  [ -d "$REPO_ROOT/$APP_WORKSPACE" ]
}

workspace_has_scheme() {
  xcodebuild -list -workspace "$REPO_ROOT/$APP_WORKSPACE" 2>/dev/null |
    grep -Eq "^[[:space:]]+$APP_SCHEME$"
}

ensure_workspace_generated() {
  if workspace_is_generated && workspace_has_scheme; then
    return 0
  fi

  generate_workspace
}

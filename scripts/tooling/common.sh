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

generate_workspace() {
  run_in_app run_mise_exec tuist generate --no-open
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

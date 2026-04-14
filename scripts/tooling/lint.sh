#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(cd -- "$(dirname -- "$0")" && pwd)/common.sh"

setup_local_tooling_env

hk_steps=(
  markdown
  pkl
  pkl-format
  shellcheck
  shfmt
  actionlint
  zizmor
  prettier
  ruff
  ruff_format
)

hk_args=(check --all)
for step in "${hk_steps[@]}"; do
  hk_args+=(--step "$step")
done

run_mise_exec hk "${hk_args[@]}"

if [ "$(uname -s)" = "Darwin" ]; then
  (
    cd "$REPO_ROOT/app"
    run_mise_exec swiftlint lint \
      --config .swiftlint.yml \
      --cache-path "$REPO_ROOT/.cache/swiftlint" \
      Tuist.swift \
      Workspace.swift \
      Tuist/Package.swift \
      Shorty/Project.swift \
      Shorty/Sources \
      Shorty/Tests
  )
fi

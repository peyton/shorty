#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(cd -- "$(dirname -- "$0")" && pwd)/common.sh"

setup_local_tooling_env

sh_files=()
while IFS= read -r -d '' file; do
  sh_files+=("$file")
done < <(rg --files -0 -g '*.sh' -g '*.bash' -g '*.mksh' -g '*.bats' -g '*.zsh')
if [ "${#sh_files[@]}" -gt 0 ]; then
  run_mise_exec shfmt -w --apply-ignore "${sh_files[@]}"
fi

prettier_files=()
while IFS= read -r -d '' file; do
  prettier_files+=("$file")
done < <(rg --files -0 -g '*.json' -g '*.jsonc' -g '*.md' -g '*.markdown' -g '*.yaml' -g '*.yml' -g '*.html' -g '*.css')
if [ "${#prettier_files[@]}" -gt 0 ]; then
  run_mise_exec prettier --write "${prettier_files[@]}"
fi

run_mise_exec pkl format hk.pkl
run_mise_exec ruff check --fix .
run_mise_exec ruff format .

if [ "$(uname -s)" = "Darwin" ]; then
  (
    cd "$REPO_ROOT/app"
    run_mise_exec swiftlint lint \
      --fix \
      --format \
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

#!/usr/bin/env bash
set -euo pipefail

if [ "${ACT:-}" != "true" ]; then
  exit 0
fi

if [ ! -f .git ]; then
  printf 'Git metadata is already usable for act.\n'
  exit 0
fi

gitdir_ref="$(cat .git 2>/dev/null || true)"
if [ "${gitdir_ref#gitdir: }" = "$gitdir_ref" ]; then
  printf 'Git metadata is already usable for act.\n'
  exit 0
fi

printf 'Repairing worktree git metadata for act.\n'
rm -f .git
git init -q
git config user.name act
git config user.email act@local.invalid
git add -A
git commit --allow-empty -qm "act workspace snapshot"

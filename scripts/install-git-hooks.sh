#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$repo_root"

chmod +x "$repo_root/scripts/git-hooks/post-checkout" "$repo_root/scripts/git-hooks/pre-commit"

if [[ "$(git config --get extensions.worktreeConfig || true)" == "true" ]]; then
  git config --worktree core.hooksPath scripts/git-hooks
else
  git config core.hooksPath scripts/git-hooks
fi

echo "Installed repo-local git hooks via core.hooksPath=scripts/git-hooks."

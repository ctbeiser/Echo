#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target_dd="${DERIVED_DATA_PATH:-$repo_root/DerivedData}"
warm_dd="${1:-}"

if [[ -d "$target_dd" ]]; then
  echo "DerivedData already exists: $target_dd"
  exit 0
fi

if [[ -z "$warm_dd" ]]; then
  sibling_root="$(dirname "$repo_root")"
  warm_dd="$(find "$sibling_root" -maxdepth 3 -type d -name DerivedData -not -path "$target_dd" -print -quit 2>/dev/null || true)"
fi

if [[ -z "$warm_dd" || ! -d "$warm_dd" ]]; then
  echo "No warm DerivedData found. Run a build to create $target_dd."
  exit 0
fi

mkdir -p "$(dirname "$target_dd")"
if ! cp -cR "$warm_dd" "$target_dd" 2>/dev/null; then
  cp -R "$warm_dd" "$target_dd"
fi

rm -rf \
  "$target_dd/Build" \
  "$target_dd/Index.noindex/Build" \
  "$target_dd"/*/Build \
  "$target_dd"/*/Index.noindex/Build

echo "Seeded DerivedData from $warm_dd"

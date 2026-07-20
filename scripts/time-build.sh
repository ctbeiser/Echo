#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export SCHEME="${SCHEME:-Verify Full}"
build_platform="${BUILD_PLATFORM:-simulator}"
build_action="${BUILD_ACTION:-build}"

actions=()
if [[ "${CLEAN:-0}" != "0" ]]; then
  actions+=(clean)
fi
actions+=("$build_action")

exec "$repo_root/scripts/build.sh" \
  "$build_platform" \
  "${actions[@]}" \
  -showBuildTimingSummary

#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SCHEME="${SCHEME:-solipsistweets}"
exec "$repo_root/scripts/build-simulator.sh" build-for-testing

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

MODE="${1:-build}"
if [[ $# -gt 0 ]]; then
  shift
fi

if [[ $# -eq 0 ]]; then
  set -- solipsistweets orion
fi

if ! command -v swiftlint >/dev/null 2>&1; then
  message="SwiftLint is not installed; install it with 'brew install swiftlint'."
  if [[ "$MODE" == "build" && -z "${CI:-}" ]]; then
    echo "warning: $message" >&2
    exit 0
  fi
  if [[ "${CI:-}" == "true" || "${CI:-}" == "1" ]]; then
    echo "error: $message" >&2
    exit 1
  fi
  echo "error: $message" >&2
  exit 127
fi

case "$MODE" in
  build)
    swiftlint lint \
      --config "$ROOT_DIR/.swiftlint-build.yml" \
      --working-directory "$ROOT_DIR" \
      --strict \
      --quiet \
      --reporter xcode \
      "$@"
    ;;
  lint)
    swiftlint lint \
      --config "$ROOT_DIR/.swiftlint.yml" \
      --working-directory "$ROOT_DIR" \
      --strict \
      --quiet \
      --reporter xcode \
      "$@"
    ;;
  fix|autofix)
    swiftlint lint \
      --fix \
      --format \
      --config "$ROOT_DIR/.swiftlint-autofix.yml" \
      --working-directory "$ROOT_DIR" \
      --quiet \
      "$@"
    ;;
  *)
    echo "usage: $0 [build|lint|fix] [paths...]" >&2
    exit 64
    ;;
esac

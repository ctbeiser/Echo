#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

platform="${1:-simulator}"
if [[ $# -gt 0 ]]; then
  shift
fi

project="${PROJECT:-$repo_root/solipsistweets.xcodeproj}"
scheme="${SCHEME:-solipsistweets}"
configuration="${CONFIGURATION:-Debug}"
derived_data_path="${DERIVED_DATA_PATH:-$repo_root/DerivedData}"

args=(
  -disableAutomaticPackageResolution
  -project "$project"
  -scheme "$scheme"
  -configuration "$configuration"
  -derivedDataPath "$derived_data_path"
  COMPILER_INDEX_STORE_ENABLE="${COMPILER_INDEX_STORE_ENABLE:-NO}"
  ENABLE_DEBUG_DYLIB="${ENABLE_DEBUG_DYLIB:-NO}"
  ENABLE_TESTABILITY="${ENABLE_TESTABILITY:-NO}"
  ENABLE_PREVIEWS="${ENABLE_PREVIEWS:-NO}"
  STRING_CATALOG_GENERATE_SYMBOLS="${STRING_CATALOG_GENERATE_SYMBOLS:-NO}"
  SWIFT_EMIT_LOC_STRINGS="${SWIFT_EMIT_LOC_STRINGS:-NO}"
)

case "$platform" in
  simulator)
    destination="${SIMULATOR_DESTINATION:-generic/platform=iOS Simulator}"
    if [[ "$destination" != *"platform=iOS Simulator"* ]]; then
      echo "error: SIMULATOR_DESTINATION must select an iOS Simulator destination." >&2
      exit 64
    fi
    args+=(
      -destination "$destination"
      ARCHS="${BUILD_ARCHS:-$(uname -m)}"
      ONLY_ACTIVE_ARCH="${ONLY_ACTIVE_ARCH:-YES}"
      CODE_SIGNING_ALLOWED=NO
      CODE_SIGN_STYLE=Manual
    )
    ;;
  device)
    destination="${DEVICE_DESTINATION:-generic/platform=iOS}"
    if [[ "$destination" != *"platform=iOS"* || "$destination" == *Simulator* ]]; then
      echo "error: DEVICE_DESTINATION must select a physical or generic iOS device." >&2
      exit 64
    fi
    args+=(
      -destination "$destination"
      -allowProvisioningUpdates
      -allowProvisioningDeviceRegistration
      CODE_SIGNING_ALLOWED=YES
      CODE_SIGNING_REQUIRED=YES
      CODE_SIGN_STYLE="${CODE_SIGN_STYLE:-Automatic}"
    )
    if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
      args+=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM")
    fi
    ;;
  *)
    echo "usage: $0 [simulator|device] [xcodebuild action or option ...]" >&2
    exit 64
    ;;
esac

if [[ $# -eq 0 ]]; then
  set -- build
fi

xcodebuild "${args[@]}" "$@"

#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

project="${PROJECT:-$repo_root/solipsistweets.xcodeproj}"
scheme="${SCHEME:-Verify Full}"
configuration="${CONFIGURATION:-Debug}"
destination="${DESTINATION:-generic/platform=iOS Simulator}"
timing_derived_data="${TIMING_DERIVED_DATA:-$repo_root/.context/build-timing/$scheme}"
build_action="${BUILD_ACTION:-build}"

args=(
  -disableAutomaticPackageResolution
  -project "$project"
  -scheme "$scheme"
  -configuration "$configuration"
  -destination "$destination"
  -derivedDataPath "$timing_derived_data"
  COMPILER_INDEX_STORE_ENABLE="${COMPILER_INDEX_STORE_ENABLE:-NO}"
  ENABLE_DEBUG_DYLIB="${ENABLE_DEBUG_DYLIB:-NO}"
  ENABLE_TESTABILITY="${ENABLE_TESTABILITY:-NO}"
  ENABLE_PREVIEWS="${ENABLE_PREVIEWS:-NO}"
  STRING_CATALOG_GENERATE_SYMBOLS="${STRING_CATALOG_GENERATE_SYMBOLS:-NO}"
  SWIFT_EMIT_LOC_STRINGS="${SWIFT_EMIT_LOC_STRINGS:-NO}"
)

if [[ "$destination" == *Simulator* ]]; then
  args+=(
    ARCHS="${BUILD_ARCHS:-$(uname -m)}"
    CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}"
    CODE_SIGN_STYLE="${CODE_SIGN_STYLE:-Manual}"
  )
fi

actions=()
if [[ "${CLEAN:-1}" != "0" ]]; then
  actions+=(clean)
fi
actions+=("$build_action")

xcodebuild "${args[@]}" \
  "${actions[@]}" \
  -showBuildTimingSummary

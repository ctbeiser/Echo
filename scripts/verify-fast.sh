#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

project="${PROJECT:-$repo_root/solipsistweets.xcodeproj}"
scheme="${SCHEME:-solipsistweets}"
configuration="${CONFIGURATION:-Debug}"
destination="${DESTINATION:-generic/platform=iOS Simulator}"
derived_data_path="${DERIVED_DATA_PATH:-$repo_root/DerivedData}"

args=(
  -disableAutomaticPackageResolution
  -project "$project"
  -scheme "$scheme"
  -configuration "$configuration"
  -destination "$destination"
  -derivedDataPath "$derived_data_path"
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

xcodebuild "${args[@]}" \
  build-for-testing

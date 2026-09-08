#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
configuration="${CONFIGURATION:-Debug}"
derived_data_path="${DERIVED_DATA_PATH:-$repo_root/DerivedData}"

# A local ad-hoc signature allows the sandboxed app to run without provisioning.
"$repo_root/scripts/build-mac.sh" build \
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=-
app_path="$derived_data_path/Build/Products/$configuration/Echo.app"
codesign --verify --deep --strict "$app_path"

# Replace this worktree's running build without activating it or sending keys
# to whichever app the user is working in. Do not leave an older process running.
xcrun swift - "$app_path" <<'SWIFT'
import AppKit

let appURL = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
for app in NSWorkspace.shared.runningApplications where app.bundleURL?.standardizedFileURL == appURL {
    guard app.terminate() else { fatalError("Could not quit the previous Echo build") }
    let deadline = Date().addingTimeInterval(5)
    while !app.isTerminated && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    guard app.isTerminated else { fatalError("The previous Echo build did not finish quitting") }
}
SWIFT

open -g "$app_path"

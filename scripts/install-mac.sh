#!/usr/bin/env bash
set -euo pipefail

# Adapted from Banana's Conductor install-macos.sh.
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
configuration="${CONFIGURATION:-Release}"
derived_data_path="${DERIVED_DATA_PATH:-$repo_root/DerivedData}"
applications_directory="${APPLICATIONS_DIRECTORY:-/Applications}"
build_arguments=(build)

if [[ "${RUN_VERBOSE:-0}" != "1" ]]; then
  build_arguments=(-quiet build)
fi

if [[ "$applications_directory" != /* ]]; then
  echo "error: APPLICATIONS_DIRECTORY must be an absolute path." >&2
  exit 64
fi

if [[ ! -d "$applications_directory" || ! -w "$applications_directory" ]]; then
  echo "error: Applications directory must exist and be writable: $applications_directory" >&2
  exit 1
fi

applications_directory="$(cd "$applications_directory" && pwd -P)"
installed_app_path="$applications_directory/Echo.app"

echo "Building a signed $configuration build of Echo for macOS..."
CONFIGURATION="$configuration" "$repo_root/scripts/build-mac.sh" "${build_arguments[@]}" \
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=-

built_app_path="${APP_PATH:-$derived_data_path/Build/Products/$configuration/Echo.app}"
if [[ ! -d "$built_app_path" ]]; then
  echo "error: Could not locate the built app at $built_app_path." >&2
  exit 1
fi

echo "Verifying the built app signature..."
/usr/bin/codesign --verify --deep --strict "$built_app_path"
bundle_identifier="$({ /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" \
  "$built_app_path/Contents/Info.plist"; } 2>/dev/null)" || {
  echo "error: Could not read the built app's bundle identifier." >&2
  exit 1
}

path_exists() {
  [[ -e "$1" || -L "$1" ]]
}

if path_exists "$installed_app_path"; then
  if [[ ! -d "$installed_app_path" || -L "$installed_app_path" ]]; then
    echo "error: Refusing to replace a non-app item or symlink at $installed_app_path." >&2
    exit 1
  fi

  installed_bundle_identifier="$({ /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" \
    "$installed_app_path/Contents/Info.plist"; } 2>/dev/null)" || {
    echo "error: Refusing to replace an app with an unreadable bundle identifier at $installed_app_path." >&2
    exit 1
  }

  if [[ "$installed_bundle_identifier" != "$bundle_identifier" ]]; then
    echo "error: Refusing to replace $installed_app_path because its bundle identifier differs from the built app." >&2
    exit 1
  fi
fi

staging_directory="$(mktemp -d "$applications_directory/.Echo-install.XXXXXX")"
staged_app_path="$staging_directory/Echo.app"
backup_app_path="$staging_directory/Previous-Echo.app"
backup_created=0
replacement_installed=0
installation_committed=0

cleanup() {
  status="$?"
  trap - EXIT

  if [[ "$status" -ne 0 && "$installation_committed" -eq 0 ]]; then
    if [[ "$replacement_installed" -eq 1 ]] && path_exists "$installed_app_path"; then
      /bin/rm -rf "$installed_app_path"
    fi

    if [[ "$backup_created" -eq 1 ]] && path_exists "$backup_app_path"; then
      if ! path_exists "$installed_app_path" && /bin/mv "$backup_app_path" "$installed_app_path"; then
        echo "Restored the previous Echo installation." >&2
      else
        echo "error: The previous app is preserved at $backup_app_path; it could not be restored automatically." >&2
        exit "$status"
      fi
    fi
  fi

  /bin/rm -rf "$staging_directory"
  exit "$status"
}
trap cleanup EXIT

echo "Staging Echo for installation..."
/usr/bin/ditto "$built_app_path" "$staged_app_path"
/usr/bin/codesign --verify --deep --strict "$staged_app_path"

# Stop installed and workspace copies gracefully so their WebKit sessions save
# before replacing the app, and only the new version remains in the menu bar.
echo "Closing the previous Echo version..."
xcrun swift - "$bundle_identifier" <<'SWIFT'
import AppKit

let apps = NSRunningApplication.runningApplications(withBundleIdentifier: CommandLine.arguments[1])
for app in apps {
    guard app.terminate() else { fatalError("Could not quit the previous Echo build") }
}
let deadline = Date().addingTimeInterval(5)
while apps.contains(where: { !$0.isTerminated }) && Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}
guard apps.allSatisfy(\.isTerminated) else { fatalError("The previous Echo build did not finish quitting") }
SWIFT

if path_exists "$installed_app_path"; then
  /bin/mv "$installed_app_path" "$backup_app_path"
  backup_created=1
fi

/bin/mv "$staged_app_path" "$installed_app_path"
replacement_installed=1
/usr/bin/codesign --verify --deep --strict "$installed_app_path"
installation_committed=1

echo "Installed Echo at $installed_app_path. Launching in the background..."
/usr/bin/open -g "$installed_app_path"

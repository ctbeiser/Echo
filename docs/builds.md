# Building and verifying Echo

Run commands from the repository root. The native Mac app requires macOS 27 and Xcode 27 or newer for WebKit’s `NSRefreshController`.

## Build And Verification

Use the fastest verification script that covers the files you touched.

Use Verify Fast (`scripts/verify-fast.sh`) for changes isolated to the app target. The script defaults to the `solipsistweets` scheme.

Use Verify Full (`scripts/verify-full.sh`) when a change touches project settings, build scripts, or anything that should use the full verification path. It builds the iOS `Verify Full` scheme. This repository has two app schemes, `solipsistweets` (iOS/iPadOS) and `EchoMac` (native macOS), and no watch target. Run `scripts/build-mac.sh` for macOS changes, and both Verify Full and the macOS build for shared source, project, or build-script changes.

GitHub Actions runs `.github/workflows/ios-ci.yml` for pull requests, pushes to `main`, and manual dispatches. CI checks SwiftLint formatting and strict lint for `solipsistweets`, `EchoShareExtension`, `EchoMac`, and `Shared`, then runs `scripts/verify-full.sh` as an unsigned simulator build and `scripts/build-mac.sh` as an unsigned native macOS build. Signed device builds and installs remain local-only.

Use `scripts/build-simulator.sh` for a general compiler or smoke-check build and `scripts/build-device.sh` only when a signed iphoneos product is intentionally required. Both use repo-local `DerivedData/`; the simulator build is always unsigned and cannot inherit a physical-device destination. Override their destinations with `SIMULATOR_DESTINATION=...` or `DEVICE_DESTINATION=...`, respectively.

Use `scripts/run-mac.sh` to build, ad-hoc sign, verify, and launch the menu bar app in the background without activation. Launches and reopen events must not present the popover or take focus; presentation is reserved for explicit menu-bar/menu actions and supported URL drops onto the bird. The macOS build uses the same repo-local `DerivedData/`, defaults to the `EchoMac` scheme and host architecture, and supports `MAC_DESTINATION=...`. `scripts/build-mac.sh` is unsigned by default. A distributable Mac app requires a separately signed/notarized production archive.

Use `scripts/install-mac.sh`, also available as Conductor's **Install Mac** Run action, to build an ad-hoc signed Release app and install it at `/Applications/Echo.app`. Adapted from Banana's installer, it stages and verifies the bundle before gracefully quitting running Echo copies, replaces only an app with the same bundle identifier, and restores the previous installation if replacement or signature verification fails. It then launches the installed copy with `open -g`, without opening the popover or taking focus. Set `CONFIGURATION`, `DERIVED_DATA_PATH`, or `APP_PATH` to override the build configuration or product location, `APPLICATIONS_DIRECTORY` to select an existing writable absolute installation directory, and `RUN_VERBOSE=1` for full build output. This is a local ad-hoc installation, not a notarized distribution build.

Use `scripts/run-device.sh` to build the `solipsistweets` scheme, verify its signature, install it on a paired iPhone over Wi-Fi, and launch it. If more than one wireless iPhone is available, set `DEVICE_ID` to a listed device name, identifier, or UDID. This remains the default Conductor Run action. Both it and Install Mac are local-only and nonconcurrent because the physical device and installed app are shared across workspaces. Runs keep output concise by default while native `xcodebuild` warnings and errors and `devicectl` errors remain visible. Set `RUN_VERBOSE=1` to restore full `xcodebuild` and `devicectl` output.

Conductor reads shared `.conductor/settings.toml` from the remote default branch. To expose an added Run action before merge on this Mac, mirror the Run entries into the repository root's `.conductor/settings.local.toml`, preserving its other settings. Commands still run from the selected workspace.

For production-scheme validation such as app packaging, project wiring, signing-sensitive behavior, platform support, or release-only settings, run the affected Xcode scheme directly with the needed destination/configuration. There is no separate watch/full verification script in this repo.

All verification scripts use repo-local `DerivedData/`, pass `-disableAutomaticPackageResolution`, disable the compiler index store with `COMPILER_INDEX_STORE_ENABLE=NO`, disable debug dylib generation with `ENABLE_DEBUG_DYLIB=NO`, disable testability with `ENABLE_TESTABILITY=NO`, disable previews/string-symbol/localized-string generation, and use simulator-only no-signing settings `CODE_SIGNING_ALLOWED=NO` plus `CODE_SIGN_STYLE=Manual`. This repo currently has no SwiftPM package dependencies; do not add package-resolution/cache infrastructure unless dependencies are introduced.

For simulator builds, the shared build scripts constrain `ARCHS` to the host architecture and set `ONLY_ACTIVE_ARCH=YES` by default to avoid building unused simulator slices. Override with `BUILD_ARCHS=...` or `ONLY_ACTIVE_ARCH=...` only when broader simulator architecture coverage is intentional.

For build timing, use `scripts/time-build.sh`. It reuses repo-local `DerivedData/` and enables Xcode's build timing summary. By default it times an incremental `build` of the `Verify Full` scheme; set `BUILD_ACTION=build-for-testing` or `CLEAN=1` when needed.

## Tests

This repo does not maintain unit-test or UI-test targets, and tests are not part of routine development here. Do not add test targets, test schemes, test plans, XCTest/Testing dependencies, or test source folders as part of normal changes.

New code still needs verification. Use the fastest verification script that covers the files touched, and broaden to Verify Full (`scripts/verify-full.sh`) when the change affects project settings or build behavior.

If a future change truly requires executable tests, first document why build, lint, and manual verification are insufficient and why the behavior can be tested with lower risk than leaving it untested. Keep that testing infrastructure scoped to the need and update this guidance in the same change.

## Project Settings

Keep the app target on Swift 6 language mode with warnings as errors, complete strict concurrency, strict memory safety, and explicit `any` existential checking. Do not weaken these settings to make a change compile; fix the source issue or document why a temporary exception is required.

Keep fast-build overhead low without bypassing lint: Xcode target lint phases run `scripts/swiftlint.sh build` with explicit config/script/source-directory inputs and stamp outputs so Xcode controls dependency analysis. Verification scripts apply build-test overrides to disable previews, testability, generated string catalog symbols, and localized string emission; real app schemes keep the Moods-style real-build settings.

Keep launch schemes useful for debugging. Launch schemes should reduce system log noise and make invalid geometry reports actionable when possible.

Release app products should validate products during build. Keep `VALIDATE_PRODUCT = YES` for production release targets.

Avoid broad platform expansion unless the product intentionally supports it. This repo supports iOS/iPadOS and a separate native macOS 27+ menu bar app. Keep `solipsistweets` and `EchoShareExtension` iOS-only and `EchoMac` macOS-only; do not add Mac Catalyst, Designed for iPhone/iPad on Mac, visionOS, or XR support by accident while editing target settings.

Keep `ENABLE_USER_SCRIPT_SANDBOXING = NO`; project build phases may need access that Xcode's user script sandbox blocks.

## DerivedData

Keep DerivedData local to the worktree at `DerivedData/`. It is ignored by Git, and all build, verification, timing, and device-run scripts use that same directory by default so their caches can be reused.

For a new worktree, `scripts/seed-derived-data.sh` can copy a warm sibling `DerivedData/` using APFS clone-copy semantics when available, then removes path-sensitive build state. Install the optional best-effort hooks with `scripts/install-git-hooks.sh`; the post-checkout hook seeds DerivedData if absent without blocking checkout on failure.

## Lint

SwiftLint is configured with focused safety/correctness rules in `.swiftlint.yml` and runs in strict mode. Broad size/name/shape rules and current style-only noise are disabled so formatting preferences do not drown out safety checks or block routine builds.

Run build-time lint with `scripts/swiftlint.sh build`; Xcode target phases run the same command during verification builds. Missing SwiftLint is a local warning but a CI error. Run the base config directly with `scripts/swiftlint.sh lint`. Run autofix-only style cleanup with `scripts/swiftlint.sh fix`. With no paths supplied, both commands cover `solipsistweets`, `EchoShareExtension`, `EchoMac`, and `Shared`.

Install the optional pre-commit hook with `scripts/install-git-hooks.sh`; it sets `core.hooksPath` to `scripts/git-hooks`, runs the separate `.swiftlint-autofix.yml` path with SwiftLint `--fix --format` on staged Swift files, re-stages fixes, and aborts if a staged Swift file also has unstaged edits. Keep broad style gates out of strict lint unless existing code is baselined or fixed separately.

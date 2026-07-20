# AGENTS.md

## Build And Verification

Use the fastest verification script that covers the files you touched.

Use Verify Fast (`scripts/verify-fast.sh`) for changes isolated to the app target. The script defaults to the `solipsistweets` scheme.

Use Verify Full (`scripts/verify-full.sh`) when a change touches project settings, build scripts, or anything that should use the full verification path. It builds the `Verify Full` scheme. This repository has one app scheme, `solipsistweets`, and no watch target.

GitHub Actions runs `.github/workflows/ios-ci.yml` for pull requests, pushes to `main`, and manual dispatches. CI checks SwiftLint formatting and strict lint for both the app and share extension, then runs `scripts/verify-full.sh` as an unsigned simulator build. Signed device builds and installs remain local-only.

Use `scripts/build-simulator.sh` for a general compiler or smoke-check build and `scripts/build-device.sh` only when a signed iphoneos product is intentionally required. Both use repo-local `DerivedData/`; the simulator build is always unsigned and cannot inherit a physical-device destination. Override their destinations with `SIMULATOR_DESTINATION=...` or `DEVICE_DESTINATION=...`, respectively.

Use `scripts/run-device.sh` to build the `solipsistweets` scheme, verify its signature, install it on a paired iPhone over Wi-Fi, and launch it. If more than one wireless iPhone is available, set `DEVICE_ID` to a listed device name, identifier, or UDID. The shared Conductor Run action invokes this script locally and is nonconcurrent because the physical device is shared. Runs keep output concise by default while native `xcodebuild` warnings and errors and `devicectl` errors remain visible. Set `RUN_VERBOSE=1` to restore full `xcodebuild` and `devicectl` output.

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

Avoid broad platform expansion unless the product intentionally supports it. This repo supports iOS/iPadOS only; do not add Mac Catalyst, Designed for iPhone/iPad on Mac, visionOS, or XR support by accident while editing target settings.

Keep `ENABLE_USER_SCRIPT_SANDBOXING = NO`; project build phases may need access that Xcode's user script sandbox blocks.

## DerivedData

Keep DerivedData local to the worktree at `DerivedData/`. It is ignored by Git, and all build, verification, timing, and device-run scripts use that same directory by default so their caches can be reused.

For a new worktree, `scripts/seed-derived-data.sh` can copy a warm sibling `DerivedData/` using APFS clone-copy semantics when available, then removes path-sensitive build state. Install the optional best-effort hooks with `scripts/install-git-hooks.sh`; the post-checkout hook seeds DerivedData if absent without blocking checkout on failure.

## Lint

SwiftLint is configured with focused safety/correctness rules in `.swiftlint.yml` and runs in strict mode. Broad size/name/shape rules and current style-only noise are disabled so formatting preferences do not drown out safety checks or block routine builds.

Run build-time lint with `scripts/swiftlint.sh build`; Xcode target phases run the same command during verification builds. Missing SwiftLint is a local warning but a CI error. Run the base config directly with `scripts/swiftlint.sh lint`. Run autofix-only style cleanup with `scripts/swiftlint.sh fix`. With no paths supplied, both commands cover `solipsistweets` and `EchoShareExtension`.

Install the optional pre-commit hook with `scripts/install-git-hooks.sh`; it sets `core.hooksPath` to `scripts/git-hooks`, runs the separate `.swiftlint-autofix.yml` path with SwiftLint `--fix --format` on staged Swift files, re-stages fixes, and aborts if a staged Swift file also has unstaged edits. Keep broad style gates out of strict lint unless existing code is baselined or fixed separately.

## Source Practices

Prefer typed boundary models over raw dictionaries or half-decoded payloads. Use `String?` only when absence has meaning, keep one source of truth for mutable state, and prefer structs/enums unless identity, shared mutable state, UIKit inheritance, or Objective-C interop requires a class.

Use weak captures in long-lived closures, Combine sinks, timers, animation completions, and tasks that capture UI or store objects. Keep UI mutation on the main actor with `await MainActor.run { ... }` or `Task { @MainActor [weak self] in ... }`.

Treat app-owned static assets and parser setup as invariants. Fail fast when required named assets or static regular expressions are missing or invalid; handle user and server data as recoverable input.

For manual UIKit layout, do size-dependent work in `layoutSubviews()` or after `viewDidLayoutSubviews()`, ask subviews for size with `sizeThatFits(_:)`, prefer `bounds.size` plus `center`, and centralize padding and spacing constants.

Treat stale documentation as a correctness bug. When a change alters architecture, ownership, build behavior, invariants, or platform constraints, update the relevant repo documentation in the same change.

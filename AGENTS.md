# AGENTS.md

## Build And Verification

Use the fastest verification script that covers the files you touched.

Use Verify Fast (`scripts/verify-fast.sh`) for changes isolated to one app target. Set `SCHEME=orion` when the change only needs the Orion target; otherwise the script defaults to `solipsistweets`.

Use Verify Full (`scripts/verify-full.sh`) when a change touches shared Swift files under `solipsistweets/`, project settings, build scripts, assets used by both apps, or anything that should compile for both app schemes. It builds the shared `Verify Full` scheme, which compiles both app targets in one Xcode invocation. This repository has two app schemes, `solipsistweets` and `orion`, and no watch target.

For production-scheme validation such as app packaging, project wiring, signing-sensitive behavior, platform support, or release-only settings, run the affected shared Xcode scheme directly with the needed destination/configuration. There is no separate watch/full verification script in this repo.

All verification scripts use repo-local `DerivedData/`, pass `-disableAutomaticPackageResolution`, disable the compiler index store with `COMPILER_INDEX_STORE_ENABLE=NO`, disable debug dylib generation with `ENABLE_DEBUG_DYLIB=NO`, disable testability with `ENABLE_TESTABILITY=NO`, disable previews/string-symbol/localized-string generation, and use simulator-only no-signing settings `CODE_SIGNING_ALLOWED=NO` plus `CODE_SIGN_STYLE=Manual`. This repo currently has no SwiftPM package dependencies; do not add package-resolution/cache infrastructure unless dependencies are introduced.

For simulator builds, the app-only and fast verification scripts constrain `ARCHS` to the host architecture by default to avoid building unused simulator slices. Override with `BUILD_ARCHS=...` only when broader simulator architecture coverage is intentional.

For build timing, use `scripts/time-build.sh`. It keeps timing build products under `.context/build-timing/` and enables Xcode's build timing summary. By default it times a clean `build` of the `Verify Full` scheme; set `SCHEME=orion`, `BUILD_ACTION=build-for-testing`, or `CLEAN=0` when needed.

## Tests

This repo does not maintain unit-test or UI-test targets, and tests are not part of routine development here. Do not add test targets, test schemes, test plans, XCTest/Testing dependencies, or test source folders as part of normal changes.

New code still needs verification. Use the fastest verification script that covers the files touched, and broaden to Verify Full (`scripts/verify-full.sh`) when the change affects shared code, project settings, or both app targets.

If a future change truly requires executable tests, first document why build, lint, and manual verification are insufficient and why the behavior can be tested with lower risk than leaving it untested. Keep that testing infrastructure scoped to the need and update this guidance in the same change.

## Project Settings

Keep app targets on Swift 6 language mode with warnings as errors, complete strict concurrency, strict memory safety, and explicit `any` existential checking. Do not weaken these settings to make a change compile; fix the source issue or document why a temporary exception is required.

Keep fast-build overhead low without bypassing lint: Xcode target lint phases run `scripts/swiftlint.sh build` with explicit config/script/source-directory inputs and stamp outputs so Xcode controls dependency analysis. Verification scripts apply build-test overrides to disable previews, testability, generated string catalog symbols, and localized string emission; real app schemes keep the Moods-style real-build settings.

Keep launch schemes useful for debugging. Shared launch schemes should reduce system log noise and make invalid geometry reports actionable when possible.

Release app products should validate products during build. Keep `VALIDATE_PRODUCT = YES` for production release targets.

Avoid broad platform expansion unless the product intentionally supports it. This repo supports iOS/iPadOS only; do not add Mac Catalyst, Designed for iPhone/iPad on Mac, visionOS, or XR support by accident while editing target settings.

Keep `ENABLE_USER_SCRIPT_SANDBOXING = NO`; project build phases may need access that Xcode's user script sandbox blocks.

## DerivedData

Keep DerivedData local to the worktree at `DerivedData/`. It is ignored by Git.

## Lint

SwiftLint is configured with focused safety/correctness rules in `.swiftlint.yml` and runs in strict mode. Broad size/name/shape rules and current style-only noise are disabled so formatting preferences do not drown out safety checks or block routine builds.

Run build-time lint with `scripts/swiftlint.sh build`; Xcode target phases run the same command during verification builds. Missing SwiftLint is a local warning but a CI error. Run the base config directly with `scripts/swiftlint.sh lint`. Run autofix-only style cleanup with `scripts/swiftlint.sh fix`. Keep broad style gates out of strict lint unless existing code is baselined or fixed separately.

## Source Practices

Prefer typed boundary models over raw dictionaries or half-decoded payloads. Use `String?` only when absence has meaning, keep one source of truth for mutable state, and prefer structs/enums unless identity, shared mutable state, UIKit inheritance, or Objective-C interop requires a class.

Use weak captures in long-lived closures, Combine sinks, timers, animation completions, and tasks that capture UI or store objects. Keep UI mutation on the main actor with `await MainActor.run { ... }` or `Task { @MainActor [weak self] in ... }`.

Treat app-owned static assets and parser setup as invariants. Fail fast when required named assets or static regular expressions are missing or invalid; handle user and server data as recoverable input.

For manual UIKit layout, do size-dependent work in `layoutSubviews()` or after `viewDidLayoutSubviews()`, ask subviews for size with `sizeThatFits(_:)`, prefer `bounds.size` plus `center`, and centralize padding and spacing constants.

Treat stale documentation as a correctness bug. When a change alters architecture, ownership, build behavior, invariants, or platform constraints, update the relevant repo documentation in the same change.

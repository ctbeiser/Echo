# AGENTS.md

## Verification

Use `scripts/verify-fast.sh` for changes isolated to the iOS app target.
See [docs/builds.md](docs/builds.md) for Mac/shared verification and all build, lint, signing, and test guidance.

## Source Practices

Prefer typed boundary models over raw dictionaries or half-decoded payloads. Use `String?` only when absence has meaning, keep one source of truth for mutable state, and prefer structs/enums unless identity, shared mutable state, UIKit inheritance, or Objective-C interop requires a class.

Use weak captures in long-lived closures, Combine sinks, timers, animation completions, and tasks that capture UI or store objects. Keep UI mutation on the main actor with `await MainActor.run { ... }` or `Task { @MainActor [weak self] in ... }`.

Treat app-owned static assets and parser setup as invariants. Fail fast when required named assets or static regular expressions are missing or invalid; handle user and server data as recoverable input.

For manual UIKit layout, do size-dependent work in `layoutSubviews()` or after `viewDidLayoutSubviews()`, ask subviews for size with `sizeThatFits(_:)`, prefer `bounds.size` plus `center`, and centralize padding and spacing constants.

Treat stale documentation as a correctness bug. When a change alters architecture, ownership, build behavior, invariants, or platform constraints, update the relevant repo documentation in the same change.

`Shared/` is compiled by both app targets; keep UIKit dependencies behind iOS conditionals. The Mac UI is a fixed-size, non-detachable `NSPopover`, not a resizable window. Load visible notification pages only when that account's popover is presented. Background monitors must use neutral pages and read-only count requests, never mark notifications read, and keep credentials inside WebKit. Unavailable/stale counts must not become zero. Clear a known count locally when the selected account displays its loaded notifications page; cancel older monitor samples and let the website handle its own read state. See `README.md` for the count protocol and manual verification workflow.

Attach WebKit's native `NSRefreshController` to each visible browsing session, and let WebKit handle the pull gesture and system indicator. End refreshing on completion, failure, hiding, and shutdown. Do not implement a custom wheel/DOM refresh detector or replacement indicator. Background count monitors must not have refresh controllers.

Keep each Mac website in its own clipped page container with a directly sized `WKWebView`. The pager must not be an outer scrolling document. Horizontal paging must keep page origins fixed vertically and preserve each website’s full vertical event sequence and scroll position. Only claim horizontal gestures toward an adjacent account; outward gestures must stay with the website for their complete sequence, including reversals and momentum. Route page gestures locally; the toolbar and other popover controls must not intercept them.

`DesktopPagesView` must observe `DesktopStore` directly. Verify the SwiftUI-hosted content's presentation, selection, and gesture updates; standalone native pager checks cannot catch a broken state connection.

# Echo

Echo opens Twitter and Bluesky (through cope.works) with home feeds hidden, starts at notifications, and tracks time spent using the app.

The `solipsistweets` scheme builds the iPhone/iPad app and its Open in Echo share extension. The `EchoMac` scheme builds a separate native macOS 27+ menu bar app and requires Xcode 27 or newer, for WebKit's built-in pull-to-refresh support.

## Run on Mac

Choose **Install Mac** from Conductor's Run menu to install and launch `/Applications/Echo.app` without taking focus, or run `scripts/install-mac.sh`. See [the build guide](docs/builds.md) for installation options. For a workspace-only build:

```sh
scripts/run-mac.sh
```

This builds and locally signs `DerivedData/Build/Products/Debug/Echo.app`, then launches it in the background without activating it. Open the popover by clicking the menu-bar bird or dropping an X or Bluesky URL onto it. Launching, reopening, login startup, and incoming URL-scheme events never open the popover or take focus. No paid developer account or provisioning is required for this local ad-hoc build. You can also run the `EchoMac` scheme in Xcode. For distribution, archive that scheme with the appropriate Developer ID signing and notarization; the local script does not produce a notarized release.

Click the bird in the menu bar to open a fixed 443 × 960 popover (6:13 rounded to whole points, including the toolbar and divider). It closes when you click outside or click the bird again, and cannot be resized or detached. Choose Twitter, Bluesky, or both, then sign in inside Echo. Sign-ins persist independently of Safari and the iOS app. Account switching preserves each page. Closing the popover leaves the menu bar app running.

Drag a browser link, address-bar URL, or selected URL text onto the bird to open it in the popover. Echo highlights the icon for supported `x.com`, `twitter.com`, `bsky.app`, and `cope.works` web links, selects or adds the matching account, and opens the dropped page directly. Bluesky links use cope.works, preserving their path, query, and fragment. Unrelated links, files, and non-URL text are ignored; hovering or cancelling a drag does not navigate or open the popover.

When opening by clicking the bird, Echo selects the account with unread notifications if exactly one account has a fresh nonzero count and the other has a fresh zero count. If both have notifications, neither does, or either count is unavailable or stale, it keeps the last selected account. Selection happens before presentation, without a slide or briefly loading the previous account. It uses existing counts without extra polling and preserves each website's current page. Explicit account choices from the menu and dropped URLs select their requested account.

The toolbar centers a single Liquid Glass account tab control between Back and the actions menu. A shared selection capsule slides between tabs, follows horizontal page swipes, and settles with the page. Left/right arrow keys switch accounts when the control has keyboard focus; Reduce Motion disables its settling animation. An inactive account's nonzero unread count replaces its icon; selected accounts and accounts without a nonzero count retain their icons. The actions menu provides account setup/removal, count refresh, and Quit. Links to other sites open in your default browser. `echodotapp:` and `e:` links use the same routing as iOS. Right-click the bird for per-account counts, refresh, Launch at Login, and Quit. Keep the app in Applications before enabling Launch at Login. This setting is opt-in.

With both accounts configured, Bluesky is on the left and Twitter is on the right. Swipe left across Bluesky to move to Twitter, and swipe right across Twitter to return. Both pages move together with the trackpad gesture. Releasing a long drag or a quick flick settles onto the adjacent page; short drags slide back. Vertical gestures and horizontal pans toward an outside edge stay with the website, including their beginning, later direction changes, and momentum. This lets leftward pans scroll Twitter's image carousels without moving the account page. Once a gesture starts paging between accounts, reversing it can return to its starting position but cannot overscroll the outer edge. Browser history remains available through Back and ⌘[ / ⌘]; its trackpad gesture is used for account switching when both panels are enabled.

Each website lives in its own clipped AppKit page container, and its `WKWebView` is sized directly to that container. The pager has no scrolling document: it moves the containers only along the horizontal axis. Gesture routing belongs to these web views, not a popover-wide event monitor. The initial events are held until the gesture’s axis and direction are known. A vertical or outward gesture is delivered intact to its original website; only horizontal gestures toward an adjacent account belong to the pager. Page movement preserves each document’s size and vertical scroll position.

Pull down at the top of either website to reload it using macOS's built-in [`NSRefreshController`](https://developer.apple.com/documentation/appkit/nsrefreshcontroller), attached directly to each `WKWebView`. WebKit handles the pull gesture and system indicator; Echo reloads the page when the controller fires and ends the indicator on completion, failure, closing the page, or shutdown. Background count monitors have no refresh controller.

The popover opens without preselecting a control or displaying a focus ring. Tab and Shift-Tab enter normal keyboard navigation. Keyboard shortcuts while Echo is open: ⌘N for notifications, ⌘R to reload, ⌘[ / ⌘] for back/forward, ⌘2 to switch accounts, and ⌘Q to quit. Foreground screen time is tracked separately from background monitoring. The popover has no notification-count or polling-status footer.

## Menu bar counts

Counts represent unread social notifications across configured services, excluding direct messages and other apps' macOS notifications. Echo uses separate background WebKit sessions on neutral settings pages; visible notification pages load only when the user opens the corresponding account. Viewing a loaded notifications page immediately clears that account’s known unread count locally. This applies on opening the popover, switching accounts, and navigating back to notifications within a website. Profiles, other pages, failed loads, and neighboring pages previewed during a swipe do not clear counts. Echo records this as a local read acknowledgment, retires any earlier monitor document, and resumes normal background sampling after you leave. The website handles its own server-side read state; Echo sends no extra mark-read requests. Unknown counts remain unknown.

Reading views stay mounted and retain their documents and scroll positions across popover closes and account switches. Hidden accounts are hidden at the AppKit view level; reopening an already loaded page does not reload it. An account's first presentation still loads its notification page, avoiding hidden startup visits that could mark notifications read.

Twitter background samples run at randomized 5–9 minute intervals, with a randomized 30–90 second startup/wake delay and a persisted five-minute minimum between checks, including manual refresh. Bluesky checks are randomized across 60–90 seconds. Each sample loads the account's neutral `/settings` page and observes the site's own fresh badge calculation, then suspends the document. Echo never replays either site's requests or reuses Twitter's per-request transaction headers. Checks for an account are deferred while that account's popover is visible. Opening or closing the popover does not force a background reload.

Background sessions use WebKit's public [inactive scheduling policy](https://developer.apple.com/documentation/webkit/wkpreferences/inactiveschedulingpolicy-swift.property): briefly allow throttled work during a sample, then suspend on a result or after a 25-second timeout. This also suspends the hidden site's own timers between samples. Server rate-limit deadlines are persisted and enforced before further checks, including after relaunch, with an additional randomized delay. Checks neither navigate to notifications nor submit notification read mutations. Visible pages, where the user reads notifications, retain the sites' normal read behavior.

Visible browsing sessions request mobile content and use a standard iPhone Safari user agent so both sites load their mobile layouts in the popover. The Safari product version comes from the installed Safari app; the iPhone OS token uses Safari's [frozen `18_7` value](https://bugs.webkit.org/show_bug.cgi?id=298260#c10). Background count monitors retain WebKit's generated desktop platform/engine tokens and Safari's standard product tokens. There is no Echo-specific token or rotating identity.

Twitter also chooses its wide layout when both JavaScript screen dimensions are at least 500 CSS pixels, even in a narrow viewport. Its visible browsing session therefore reports the viewport's width and height through the JavaScript `Screen` API, starting before the site's scripts run. This lets Twitter render its own bottom navigation in the 443-point popover. The override is limited to canonical HTTPS Twitter main frames; background monitors and other sites keep the system's screen dimensions. Visible web views start at the popover's size so the first document never initializes against a temporary desktop-width frame.

The observer reads `ntab_unread_count` from Twitter's own notification badge response when the site supplies it. For Bluesky, it observes the website's `NOTIFS_BROADCAST_CHANNEL` result after a successful authenticated first-page [`app.bsky.notification.listNotifications`](https://github.com/bluesky-social/atproto/blob/main/lexicons/app/bsky/notification/listNotifications.json) request for all notification types. This is the website's finished badge calculation, including its handling of likes/reposts of reposts, blocks, moderation labels, mute preferences, and 30+ display limit. Echo does not independently count raw records or accept `getUnreadCount` totals. A missing badge, an initial empty badge, a failed request, or a broadcast without a fresh successful request cannot establish zero.

Only the Bluesky monitor document reports itself visible to JavaScript, allowing the site's normal badge initialization to run on `/settings`. The native WebKit view remains offscreen and is suspended as soon as the sample finishes, with a 25-second timeout. This never shows a window, activates the app, or changes visible browser sessions. Each new sample uses a fresh monitor document so cached broadcasts cannot renew a stale count. The site's own request headers, notification preferences, and filtering remain inside WebKit; no credentials or notification records cross the native bridge.

A notification-link badge provides a fallback. For Twitter, an empty badge is accepted as zero only after a fresh page has finished loading, at least ten seconds have elapsed, and the authenticated account-switcher and notification link are both present. No passwords, cookies, tokens, or response bodies are sent to Swift or persisted by the observer: its bridge accepts only a typed count/status message from a canonical HTTPS main frame. Requests use the site's current credentials inside WebKit and respect rate-limit responses.

The menu bar uses a template silhouette of the dove from Echo’s app icon, adapting to light and dark appearances. Zero counts are hidden. It shows:

| Display | Meaning |
| --- | --- |
| `12` | Nonzero unread count across available accounts; viewing notifications clears that account’s displayed count immediately |
| `30+`, `12+` | At least this many; the website supplied a capped badge |
| Bird without a number | Zero unread notifications, or no available count; hover or right-click for each account’s status |

Hover the bird or right-click it for each account's status, including any account excluded from the displayed total. A missing notification link or incomplete/sign-in page is never treated as proof of zero. Twitter counts older than 12 minutes and Bluesky counts older than four minutes become unavailable, allowing for their different polling intervals. Twitter's web endpoint and both sites' markup can change; if monitoring stops, use Refresh Counts (subject to the minimum interval). A failed background count is not itself evidence that the visible account is signed out. Background updates pause during sleep and stop when Echo quits. WebKit sign-ins are required before real account counts can be verified.

## Source and verification

`Shared/` contains account preferences, site profiles, link routing, content blockers, and screen time tracking. Both app targets compile these files. `solipsistweets/` contains the iOS UI; `EchoMac/` owns the popover, native controls, browser lifecycle, and background count monitoring. The iOS share extension remains iOS-only.

```sh
scripts/swiftlint.sh lint
scripts/verify-full.sh      # iOS app and share extension
scripts/build-mac.sh        # unsigned native macOS build
```

See [docs/builds.md](docs/builds.md) for verification scope, build configuration, signing, CI, lint, and the repository’s test policy.

Pager verification must exercise the actual `DesktopContentView` through SwiftUI hosting, including presentation changes, selection, hit-tested wheel events, and reopening. Calling `DesktopPagerView.update` directly does not verify the SwiftUI state connection. `DesktopPagesView` observes `DesktopStore` so the native pager receives those changes even when its parent passes the same store reference.

For menu-bar drops, drag X and Bluesky links and selected URL text onto the bird with the popover closed and open. Verify the matching page appears, including when that account has not been added; preserve the path, query, and fragment and avoid visiting notifications first. Check unsupported URLs/files/text, drag exit/cancellation, icon resizing when its count changes, ordinary clicks, and the right-click menu.

Manual verification for notification changes should cover: sign-in, two accounts, a verified zero and nonzero count, capped badges, offline/expired sessions, reading notifications, closing/reopening the popover, switching accounts without loading hidden notification pages, sleep/wake, external links, and relaunch with persistent sign-ins. Browser/API changes require signed-in checks against the live services as well as build and lint verification.

Badge parity also needs fixture checks for website-filtered results (including blocked authors and repost activity), verified zero/nonzero/capped counts, malformed or stale broadcasts, authenticated request completion, and failures. Swift compilation and lint cannot verify the injected JavaScript's behavior, and manufacturing those account states on live services would change real user data. Use disposable fixtures in the gitignored `.context` directory; no test targets or dependencies are needed.

Read-acknowledgment checks should use simulated WebKit responses at the canonical notification/profile URLs, including SPA history navigation. Verify immediate clearing on presentation, no clearing on previews or failures, and normal updates after leaving. These disposable checks avoid changing real notifications merely to exercise the UI.

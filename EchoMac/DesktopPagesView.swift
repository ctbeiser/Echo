import AppKit
import QuartzCore
import SwiftUI
import WebKit

struct DesktopPagesView: NSViewRepresentable {
    @ObservedObject var store: DesktopStore

    func makeNSView(context: Context) -> DesktopPagerView { DesktopPagerView() }

    func updateNSView(_ view: DesktopPagerView, context: Context) {
        view.onSwipe = { [weak store] action in
            switch action {
            case .pending, .passThrough, .consume: break
            case .changed(let translation): store?.updateSwipe(translation: translation)
            case .ended(let translation, let velocity): store?.endSwipe(translation: translation, velocity: velocity)
            case .cancelled: store?.endSwipe(translation: 0, velocity: 0, cancelled: true)
            }
        }
        view.onDiscreteSwipe = { [weak store] direction in store?.switchAccount(direction) }
        view.update(
            sessions: store.configuredTabs.compactMap { store.browsers[$0] },
            selection: store.accounts.activeTab,
            progress: store.swipeProgress,
            isPresented: store.isPopoverVisible,
            animated: context.transaction.animation != nil
        )
    }

    static func dismantleNSView(_ view: DesktopPagerView, coordinator: ()) { view.stop() }
}

@MainActor
protocol DesktopPageGestureHandler: AnyObject {
    func handleScroll(_ event: NSEvent, from webView: DesktopWebView) -> Bool
    func handleSwipe(_ event: NSEvent) -> Bool
}

// WebKit remains the scrolling view. The pager only takes gestures toward an
// adjacent account; vertical and outward gestures reach the website unchanged.
final class DesktopWebView: WKWebView {
    weak var pageGestureHandler: (any DesktopPageGestureHandler)?

    override func scrollWheel(with event: NSEvent) {
        if pageGestureHandler?.handleScroll(event, from: self) != true { scrollWebsite(with: event) }
    }

    func scrollWebsite(with event: NSEvent) { super.scrollWheel(with: event) }

    override func swipe(with event: NSEvent) {
        if pageGestureHandler?.handleSwipe(event) != true { super.swipe(with: event) }
    }
}

// This is a viewport, never a scroll view or a double-width document. Each
// child has its own clipping boundary and a web view exactly one page wide.
final class DesktopPagerView: NSView, DesktopPageGestureHandler {
    var onSwipe: ((AccountSwipeRecognizer.Action) -> Void)?
    var onDiscreteSwipe: ((AccountSwipeDirection) -> Void)?
    private var pages: [DesktopPageViewport] = []
    private var selection = SocialTab.x
    private var progress: CGFloat = 0
    private var isPresented = false
    private var lastLayoutSize = NSSize.zero
    private var recognizer = AccountSwipeRecognizer()
    private var pendingEvents: [NSEvent] = []
    private weak var gestureWebView: DesktopWebView?
    private var lastEventTimestamp: TimeInterval = 0
    private var gestureEnd: Task<Void, Never>?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("DesktopPagerView is created programmatically") }

    func update(sessions: [DesktopWebSession], selection: SocialTab, progress: CGFloat, isPresented: Bool, animated: Bool) {
        let changedPages = pages.count != sessions.count || zip(pages, sessions).contains { $0.session !== $1 }
        if changedPages {
            resetGesture()
            let previous = Dictionary(uniqueKeysWithValues: pages.map { ($0.session.tab, $0) })
            for page in pages where !sessions.contains(where: { $0 === page.session }) {
                page.session.webView.pageGestureHandler = nil
                page.removeFromSuperview()
            }
            pages = sessions.map { session in
                let page: DesktopPageViewport
                if let existing = previous[session.tab], existing.session === session {
                    page = existing
                } else {
                    page = DesktopPageViewport(session: session)
                    addSubview(page)
                }
                session.webView.pageGestureHandler = self
                return page
            }
        }
        if !isPresented { resetGesture() }
        self.isPresented = isPresented
        let moved = self.selection != selection || self.progress != progress
        self.selection = selection
        self.progress = progress
        for page in pages {
            page.acceptsInput = page.session.tab == selection
            page.setAccessibilityHidden(!page.acceptsInput)
        }
        if changedPages || moved { positionPages(animated: animated && !changedPages) }
    }

    override func layout() {
        super.layout()
        guard bounds.size != lastLayoutSize else { return }
        lastLayoutSize = bounds.size
        positionPages(animated: false)
    }

    private func positionPages(animated: Bool) {
        let selectedIndex = selectedPageIndex
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? 0.25 : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            for (index, page) in pages.enumerated() {
                let frame = NSRect(
                    x: (CGFloat(index - selectedIndex) + progress) * bounds.width,
                    y: 0, width: bounds.width, height: bounds.height
                )
                if animated { page.animator().frame = frame } else { page.frame = frame }
            }
        }
    }

    func handleScroll(_ event: NSEvent, from webView: DesktopWebView) -> Bool {
        guard isPresented, pages.count > 1 else { return false }
        if gestureWebView == nil || event.phase.contains(.began) || event.phase.contains(.mayBegin) ||
            (event.phase.isEmpty && event.momentumPhase.isEmpty && event.timestamp - lastEventTimestamp > 0.25) {
            gestureWebView = webView
        }
        lastEventTimestamp = event.timestamp
        let action = recognizer.handle(
            deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY,
            phase: event.phase, momentumPhase: event.momentumPhase, timestamp: event.timestamp,
            canSwipePrevious: selectedPageIndex > 0, canSwipeNext: selectedPageIndex < pages.count - 1,
            hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas
        )
        gestureEnd?.cancel()
        switch action {
        case .pending:
            // Keep the beginning with the rest of the gesture. Sending it to
            // WebKit before choosing an axis would strand a partial web gesture.
            pendingEvents.append(event)
            if pendingEvents.count >= 32 {
                recognizer.leaveGestureWithWebsite()
                flushPendingEvents()
            }

        case .passThrough:
            flushPendingEvents()
            if let gestureWebView, gestureWebView !== webView {
                gestureWebView.scrollWebsite(with: event)
                return true
            }
            return false

        case .changed, .ended, .cancelled, .consume:
            pendingEvents.removeAll(keepingCapacity: true)
            onSwipe?(action)
        }
        if event.phase.isEmpty && event.momentumPhase.isEmpty {
            gestureEnd = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(160)) } catch { return }
                guard let self else { return }
                if !pendingEvents.isEmpty { recognizer.leaveGestureWithWebsite() }
                flushPendingEvents()
                onSwipe?(recognizer.finish(timestamp: ProcessInfo.processInfo.systemUptime))
            }
        }
        return true
    }

    override func scrollWheel(with event: NSEvent) {
        // Continue a page gesture when the moving page uncovers the viewport
        // beneath the pointer. The viewport itself has no scrollable document.
        let webView = event.phase.contains(.began) ? selectedWebView : gestureWebView ?? selectedWebView
        guard let webView else { return }
        if !handleScroll(event, from: webView) { webView.scrollWebsite(with: event) }
    }

    func handleSwipe(_ event: NSEvent) -> Bool {
        guard isPresented, pages.count > 1, abs(event.deltaX) > abs(event.deltaY), event.deltaX != 0 else { return false }
        let direction: AccountSwipeDirection = event.deltaX < 0 ? .next : .previous
        let destination = selectedPageIndex + (direction == .next ? 1 : -1)
        guard pages.indices.contains(destination) else { return false }
        resetGesture()
        onDiscreteSwipe?(direction)
        return true
    }

    private var selectedPageIndex: Int { pages.firstIndex { $0.session.tab == selection } ?? 0 }

    private var selectedWebView: DesktopWebView? { pages.first { $0.session.tab == selection }?.session.webView }

    private func flushPendingEvents() {
        let events = pendingEvents
        pendingEvents.removeAll(keepingCapacity: true)
        for event in events { gestureWebView?.scrollWebsite(with: event) }
    }

    private func resetGesture() {
        gestureEnd?.cancel()
        pendingEvents.removeAll(keepingCapacity: true)
        gestureWebView = nil
        recognizer.reset()
    }

    func stop() {
        resetGesture()
        for page in pages { page.session.webView.pageGestureHandler = nil }
        onSwipe = nil
        onDiscreteSwipe = nil
    }
}

private final class DesktopPageViewport: NSView {
    let session: DesktopWebSession
    var acceptsInput = true
    private let overlay: DesktopPageOverlayView

    init(session: DesktopWebSession) {
        self.session = session
        overlay = DesktopPageOverlayView(rootView: DesktopPageOverlay(session: session))
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        overlay.sizingOptions = []
        addSubview(session.webView)
        addSubview(overlay)
    }

    required init?(coder: NSCoder) { fatalError("DesktopPageViewport is created programmatically") }

    override func layout() {
        super.layout()
        session.webView.frame = bounds
        overlay.frame = bounds
    }

    override func hitTest(_ point: NSPoint) -> NSView? { acceptsInput ? super.hitTest(point) : nil }
}

private final class DesktopPageOverlayView: NSHostingView<DesktopPageOverlay> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        rootView.session.errorMessage == nil ? nil : super.hitTest(point)
    }
}

private struct DesktopPageOverlay: View {
    @ObservedObject var session: DesktopWebSession

    var body: some View {
        ZStack(alignment: .top) {
            if session.isLoading && session.webView.refreshController?.isRefreshing != true {
                ProgressView().controlSize(.small).padding(10)
                    .background(.regularMaterial, in: Capsule()).padding(8)
                    .allowsHitTesting(false)
            }
            if let message = session.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.exclamationmark").font(.largeTitle)
                    Text("Couldn’t load this page").font(.headline)
                    Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Try Again") { session.reload() }.buttonStyle(.borderedProminent)
                }
                .padding(30)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.regularMaterial)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

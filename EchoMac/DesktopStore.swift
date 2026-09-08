import Combine
import Foundation
import SwiftUI
import WebKit

@MainActor
final class DesktopStore: ObservableObject {
    static let tabOrder: [SocialTab] = [.bluesky, .x]

    let accounts = SocialAccountStore()
    let screenTime = OnScreenTimeTracker()
    @Published private(set) var statuses: [SocialTab: NotificationStatus] = [:]
    @Published private(set) var browsers: [SocialTab: DesktopWebSession] = [:]
    @Published private(set) var isPopoverVisible = false
    @Published private(set) var swipeProgress: CGFloat = 0
    @Published private(set) var isSliding = false
    private var slideCompletion: Task<Void, Never>?

    private var monitors: [SocialTab: DesktopWebSession] = [:]
    private var timer: Timer?
    private var subscriptions: Set<AnyCancellable> = []
    private var nextChecks: [SocialTab: Date] = [:]
    private var lastChecks: [SocialTab: Date] = [:]
    private var retryDates: [SocialTab: Date] = [:]

    init() {
        accounts.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &subscriptions)
        synchronizeAccounts()
        let timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshCounts() }
        }
        timer.tolerance = 3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    var activeBrowser: DesktopWebSession? { browsers[accounts.activeTab] }

    var configuredTabs: [SocialTab] { Self.tabOrder.filter { accounts.configuredTabs.contains($0) } }

    func switcherLabel(for tab: SocialTab) -> String {
        let prefix: String
        if tab != accounts.activeTab, let count = statuses[tab]?.count, count.value > 0 {
            prefix = count.label
        } else {
            prefix = tab.emoji
        }
        return "\(prefix) \(tab.displayName)"
    }

    var menuBarLabel: String {
        let values = configuredTabs.compactMap { statuses[$0]?.count }
        let total = values.reduce(0) { $0 + $1.value }
        guard total > 0 else { return "" }
        let capped = values.contains { $0.isLowerBound }
        return "\(total)\(capped ? "+" : "")"
    }

    var statusDescription: String {
        guard !configuredTabs.isEmpty else { return "Echo — choose your accounts to get started" }
        return configuredTabs.map { tab in
            "\(tab.displayName): \(statuses[tab]?.description ?? "Notification count not available yet")"
        }.joined(separator: "\n")
    }

    func configure(_ tabs: [SocialTab]) {
        accounts.completeInitialChoice(tabs)
        synchronizeAccounts()
        updatePresentation()
    }

    func add(_ tab: SocialTab) {
        accounts.add(tab)
        synchronizeAccounts()
        updatePresentation()
    }

    func remove(_ tab: SocialTab) {
        accounts.remove(tab)
        synchronizeAccounts()
        updatePresentation()
    }

    func select(_ tab: SocialTab) {
        guard tab != accounts.activeTab else { return }
        beginSlide()
        withAnimation(.easeOut(duration: 0.25)) {
            accounts.select(tab)
            swipeProgress = 0
        }
        settleSlide()
    }

    func selectUnreadAccountForOpening() {
        let tabs = configuredTabs
        guard !isPopoverVisible, tabs.count > 1 else { return }
        let now = Date()
        let counts = tabs.compactMap { tab -> (tab: SocialTab, value: Int)? in
            guard let status = statuses[tab], let count = status.count, let updatedAt = status.updatedAt,
                  now.timeIntervalSince(updatedAt) <= BackgroundCountPolicy.freshnessLimit(for: tab) else { return nil }
            return (tab, count.value)
        }
        // An unavailable or stale count cannot establish that the other tab is empty.
        guard counts.count == tabs.count else { return }
        let unread = counts.filter { $0.value > 0 }
        guard unread.count == 1, let tab = unread.first?.tab, tab != accounts.activeTab else { return }

        // Select before presentation, without briefly loading the previous tab
        // or animating from it as the popover opens.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            cancelSlide()
            accounts.select(tab)
        }
    }

    func switchAccount() {
        guard configuredTabs.count > 1 else { return }
        select(configuredTabs[(activePageIndex + 1) % configuredTabs.count])
    }

    func switchAccount(_ direction: AccountSwipeDirection) {
        guard let index = configuredTabs.firstIndex(of: accounts.activeTab) else { return }
        let destination = index + (direction == .next ? 1 : -1)
        guard configuredTabs.indices.contains(destination) else { return }
        select(configuredTabs[destination])
    }

    func setPopoverVisible(_ visible: Bool) {
        if !visible { cancelSlide() }
        isPopoverVisible = visible
        updatePresentation()
    }

    var activePageIndex: Int { configuredTabs.firstIndex(of: accounts.activeTab) ?? 0 }

    func updateSwipe(translation: Double) {
        beginSlide()
        let progress = CGFloat(translation) / DesktopLayout.width
        let minimum: CGFloat = activePageIndex == configuredTabs.count - 1 ? 0 : -1
        let maximum: CGFloat = activePageIndex == 0 ? 0 : 1
        swipeProgress = min(max(progress, minimum), maximum)
    }

    func endSwipe(translation: Double, velocity: Double, cancelled: Bool = false) {
        let progress = CGFloat(translation) / DesktopLayout.width
        let direction: AccountSwipeDirection = progress < 0 ? .next : .previous
        let destination = activePageIndex + (direction == .next ? 1 : -1)
        let isFlick = abs(progress) > 0.04 && abs(velocity) > 450 && translation * velocity > 0
        let shouldCommit = !cancelled && (abs(progress) > 0.23 || isFlick) && configuredTabs.indices.contains(destination)
        beginSlide()
        withAnimation(.easeOut(duration: 0.25)) {
            if shouldCommit { accounts.select(configuredTabs[destination]) }
            swipeProgress = 0
        }
        settleSlide()
    }

    private func beginSlide() {
        slideCompletion?.cancel()
        guard !isSliding else { return }
        isSliding = true
        updatePresentation()
    }

    private func settleSlide() {
        updatePresentation()
        slideCompletion = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            self?.isSliding = false
            self?.updatePresentation()
        }
    }

    private func cancelSlide() {
        slideCompletion?.cancel()
        swipeProgress = 0
        isSliding = false
    }

    private func updatePresentation() {
        for (tab, browser) in browsers {
            browser.webView.allowsBackForwardNavigationGestures = configuredTabs.count < 2
            browser.setPreviewing(isPopoverVisible && isSliding)
            browser.setPresented(isPopoverVisible && tab == accounts.activeTab)
        }
    }

    private func viewedNotifications(in tab: SocialTab) {
        guard isPopoverVisible, accounts.activeTab == tab, browsers[tab]?.isViewingNotifications == true else { return }
        guard statuses[tab]?.count != nil else { return }
        if case .viewed = statuses[tab] { return }
        // Discard a sample started before the user read these notifications.
        monitors[tab]?.discardCountSample()
        statuses[tab] = .viewed(Date())
    }

    func open(_ url: URL, in tab: SocialTab) {
        accounts.add(tab)
        synchronizeAccounts()
        // Queue the destination before presenting a newly selected browser,
        // so opening a link never visits its pending notifications page first.
        browsers[tab]?.load(url)
        if isPopoverVisible {
            select(tab)
        } else {
            cancelSlide()
            accounts.select(tab)
        }
        updatePresentation()
    }

    func refreshCounts(userInitiated: Bool = false) {
        let now = Date()
        for tab in configuredTabs {
            if let updatedAt = statuses[tab]?.updatedAt, now.timeIntervalSince(updatedAt) > BackgroundCountPolicy.freshnessLimit(for: tab) {
                statuses[tab] = .unavailable("Count is out of date — waiting for the next check")
            }
            let elapsed = now.timeIntervalSince(lastChecks[tab] ?? .distantPast)
            guard elapsed >= BackgroundCountPolicy.minimumRefreshGap(for: tab),
                  now >= (retryDates[tab] ?? .distantPast),
                  browsers[tab]?.isViewingNotifications != true,
                  userInitiated || !isPopoverVisible || accounts.activeTab != tab,
                  userInitiated || now >= (nextChecks[tab] ?? .distantFuture) else { continue }
            lastChecks[tab] = now
            UserDefaults.standard.set(now, forKey: "backgroundCountLastCheck.\(tab.rawValue).v1")
            nextChecks[tab] = now.addingTimeInterval(BackgroundCountPolicy.interval(for: tab))
            monitors[tab]?.refreshCount()
        }
    }

    func resumeAfterWake() {
        for tab in configuredTabs {
            let earliest = Date().addingTimeInterval(BackgroundCountPolicy.initialDelay(for: tab))
            nextChecks[tab] = max(nextChecks[tab] ?? earliest, earliest)
        }
        refreshCounts()
    }

    func stop() {
        slideCompletion?.cancel()
        timer?.invalidate()
        timer = nil
        screenTime.stopAndFlush()
        for session in Array(browsers.values) + Array(monitors.values) { session.stop() }
    }

    private func synchronizeAccounts() {
        let tabs = Set(configuredTabs)
        for tab in Array(browsers.keys) where !tabs.contains(tab) {
            browsers.removeValue(forKey: tab)?.stop()
            monitors.removeValue(forKey: tab)?.stop()
            statuses.removeValue(forKey: tab)
            nextChecks.removeValue(forKey: tab)
            lastChecks.removeValue(forKey: tab)
            retryDates.removeValue(forKey: tab)
        }
        for tab in configuredTabs where browsers[tab] == nil {
            statuses[tab] = .checking
            let last = UserDefaults.standard.object(forKey: "backgroundCountLastCheck.\(tab.rawValue).v1") as? Date ?? .distantPast
            lastChecks[tab] = last
            retryDates[tab] = UserDefaults.standard.object(forKey: "backgroundCountRetryAfter.\(tab.rawValue).v1") as? Date
            nextChecks[tab] = max(
                Date().addingTimeInterval(BackgroundCountPolicy.initialDelay(for: tab)),
                last.addingTimeInterval(BackgroundCountPolicy.minimumRefreshGap(for: tab))
            )
            let browser = DesktopWebSession(tab: tab)
            browser.onRoute = { [weak self] url, tab in self?.open(url, in: tab) }
            browser.onViewedNotifications = { [weak self] in self?.viewedNotifications(in: tab) }
            browsers[tab] = browser
            let monitor = DesktopWebSession(tab: tab, isMonitor: true)
            monitor.onReport = { [weak self] status in
                guard let self else { return }
                statuses[tab] = status
                viewedNotifications(in: tab)
                if case .rateLimited(let until) = status {
                    let retryDate = until.addingTimeInterval(BackgroundCountPolicy.initialDelay(for: tab))
                    retryDates[tab] = retryDate
                    UserDefaults.standard.set(retryDate, forKey: "backgroundCountRetryAfter.\(tab.rawValue).v1")
                }
            }
            monitors[tab] = monitor
        }
    }
}

import AppKit
import Combine
import Foundation
import WebKit

@MainActor
final class DesktopWebSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    let tab: SocialTab
    let webView: DesktopWebView
    let isMonitor: Bool
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    var onRoute: ((URL, SocialTab) -> Void)?
    var onReport: ((NotificationStatus) -> Void)?
    var onViewedNotifications: (() -> Void)?

    private var isReady = false
    private var isPresented = false
    private var isPreviewing = false
    private var isMonitoring = false
    private var hasLoaded = false
    private var pendingURL: URL
    private var initialRefresh: Task<Void, Never>?
    private var samplingTimeout: Task<Void, Never>?
    private var urlObservation: AnyCancellable?

    init(tab: SocialTab, isMonitor: Bool = false) {
        self.tab = tab
        self.isMonitor = isMonitor
        self.pendingURL = isMonitor ? tab.monitorURL : tab.startURL

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.inactiveSchedulingPolicy = .suspend
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences.preferredContentMode = isMonitor ? .desktop : .mobile
        configuration.applicationNameForUserAgent = isMonitor ? DesktopUserAgent.safariApplicationName : nil
        if !isMonitor && tab == .x {
            configuration.userContentController.addUserScript(DesktopMobileLayout.twitterScript)
        }
        let initialSize = isMonitor ? NSSize(width: 1000, height: 800) : NSSize(width: DesktopLayout.width, height: DesktopLayout.height)
        webView = DesktopWebView(frame: NSRect(origin: .zero, size: initialSize), configuration: configuration)
        webView.customUserAgent = isMonitor ? nil : DesktopUserAgent.mobileSafari
        webView.allowsBackForwardNavigationGestures = !isMonitor
        #if DEBUG
        webView.isInspectable = true
        #endif
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        if !isMonitor {
            let refresh = NSRefreshController()
            refresh.target = self
            refresh.action = #selector(refreshFromPull)
            webView.refreshController = refresh
            // WebKit also publishes URL changes for the sites' SPA navigation.
            urlObservation = webView.publisher(for: \.url).sink { [weak self] _ in
                self?.notifyIfViewingNotifications()
            }
        }
        if isMonitor {
            configuration.userContentController.add(WeakScriptHandler(self), name: NotificationScript.handlerName)
            configuration.userContentController.addUserScript(WKUserScript(
                source: NotificationScript.source(for: tab), injectionTime: .atDocumentStart, forMainFrameOnly: true
            ))
        }
        installContentRules()
    }

    func load(_ url: URL) {
        pendingURL = focusedURL(url)
        guard isReady, isMonitor ? isMonitoring : isPresented else { hasLoaded = false; return }
        errorMessage = nil
        hasLoaded = true
        webView.load(URLRequest(url: pendingURL, timeoutInterval: 30))
    }

    func setPresented(_ presented: Bool) {
        isPresented = presented
        webView.isHidden = !presented && !isPreviewing
        if !presented { webView.refreshController?.endRefreshing() }
        if presented && !hasLoaded { load(pendingURL) }
        notifyIfViewingNotifications()
    }

    var isViewingNotifications: Bool {
        guard !isMonitor, isPresented, hasLoaded, !isLoading, !webView.isLoading, errorMessage == nil,
              let url = webView.url, tab.hasCanonicalHost(for: url), url.scheme == "https" else { return false }
        let path = url.path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path == "notifications" || path.hasPrefix("notifications/")
    }

    private func notifyIfViewingNotifications() {
        if isViewingNotifications { onViewedNotifications?() }
    }

    func setPreviewing(_ previewing: Bool) {
        isPreviewing = previewing
        webView.isHidden = !isPresented && !previewing
    }

    func reload() {
        if !isReady {
            installContentRules()
        } else {
            load(isMonitor ? tab.monitorURL : webView.url ?? pendingURL)
        }
    }

    @objc private func refreshFromPull() { reload() }

    func refreshCount() {
        guard isMonitor, !isMonitoring else { return }
        isMonitoring = true
        webView.configuration.preferences.inactiveSchedulingPolicy = .throttle
        samplingTimeout?.cancel()
        samplingTimeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(25)) } catch { return }
            guard let self else { return }
            onReport?(.unavailable("Count unavailable — refresh to retry"))
            pauseMonitoring()
        }
        // A fresh neutral document runs each site's own badge calculation once.
        // The native schedule bounds polling; visible browsers stay warm.
        reload()
    }

    private func requestCount() {
        webView.evaluateJavaScript("window.echoRefreshNotificationCount?.()") { [weak self] _, error in
            guard let self, isMonitoring else { return }
            if error != nil {
                onReport?(.unavailable("Count unavailable — refresh to retry"))
                pauseMonitoring()
            }
        }
    }

    func discardCountSample() {
        guard isMonitor else { return }
        pauseMonitoring()
        hasLoaded = false
        // Retire the old document so a suspended response cannot reappear in
        // the next sample after the user has read these notifications.
        webView.loadHTMLString("", baseURL: nil)
    }

    private func pauseMonitoring() {
        guard isMonitor else { return }
        isMonitoring = false
        initialRefresh?.cancel()
        samplingTimeout?.cancel()
        webView.stopLoading()
        // Suspend the site's own timers between samples too, so JavaScript
        // polling cannot defeat the native randomized schedule.
        webView.configuration.preferences.inactiveSchedulingPolicy = .suspend
    }

    func stop() {
        initialRefresh?.cancel()
        samplingTimeout?.cancel()
        webView.stopLoading()
        webView.refreshController?.endRefreshing()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: NotificationScript.handlerName)
        onRoute = nil
        onReport = nil
        onViewedNotifications = nil
        urlObservation = nil
    }

    private func installContentRules() {
        errorMessage = nil
        ContentBlocker.installRuleList(into: webView, identifier: tab.contentBlockerIdentifier, rulesJSON: tab.contentBlockerRulesJSON) { [weak self] installed in
            guard let self else { return }
            guard installed else {
                webView.refreshController?.endRefreshing()
                errorMessage = "Echo couldn’t prepare its content filters. Try reloading."
                onReport?(.unavailable("Content filters unavailable — retry"))
                return
            }
            isReady = true
            load(pendingURL)
        }
    }

    private func focusedURL(_ url: URL) -> URL {
        guard tab.hasCanonicalHost(for: url) else { return url }
        let path = url.path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if isMonitor, path == "notifications" || path.hasPrefix("notifications/") {
            return tab.monitorURL
        }
        if path == "home" || path == "i/timeline" {
            return isMonitor ? tab.monitorURL : tab.startURL
        }
        return url
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard isMonitor, isMonitoring, message.name == NotificationScript.handlerName,
              message.frameInfo.isMainFrame,
              message.frameInfo.securityOrigin.protocol == "https",
              tab.canonicalHosts.contains(message.frameInfo.securityOrigin.host.lowercased()),
              let body = message.body as? String,
              let data = body.data(using: .utf8),
              let report = try? JSONDecoder().decode(NotificationReport.self, from: data),
              let status = report.status else { return }
        onReport?(status)
        pauseMonitoring()
    }

    // swiftlint:disable implicitly_unwrapped_optional
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        errorMessage = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        errorMessage = nil
        webView.refreshController?.endRefreshing()
        notifyIfViewingNotifications()
        guard isMonitor, isMonitoring else { return }
        initialRefresh?.cancel()
        initialRefresh = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(12))
            } catch { return }
            self?.requestCount()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        handleFailure(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        handleFailure(error)
    }
    // swiftlint:enable implicitly_unwrapped_optional

    private func handleFailure(_ error: any Error) {
        let nsError = error as NSError
        guard !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled),
              !(nsError.domain == WKError.errorDomain && nsError.code == 102) else { return }
        webView.refreshController?.endRefreshing()
        isLoading = false
        errorMessage = error.localizedDescription
        onReport?(.unavailable("Couldn’t connect — retry when you’re online"))
        pauseMonitoring()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.refreshController?.endRefreshing()
        hasLoaded = false
        if isMonitor {
            onReport?(.unavailable("Count unavailable — waiting for the next check"))
            pauseMonitoring()
        } else if isPresented {
            reload()
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url, let scheme = url.scheme?.lowercased() else {
            decisionHandler(.cancel)
            return
        }
        let isTopLevel = action.targetFrame?.isMainFrame ?? true
        guard isTopLevel else {
            decisionHandler(["https", "http", "about", "blob", "data"].contains(scheme) ? .allow : .cancel)
            return
        }
        if scheme == "https" || scheme == "http" {
            let focused = focusedURL(url)
            if focused != url {
                decisionHandler(.cancel)
                load(focused)
                return
            }
            if tab.hasCanonicalHost(for: url) || action.navigationType != .linkActivated && action.targetFrame != nil {
                // Preserve authentication redirects, including a custom Bluesky PDS.
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
                route(url)
            }
        } else if scheme == "about" || scheme == "blob" || scheme == "data" {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
            if EchoURLScheme.isAppScheme(scheme) || ["twitter", "tweetie", "x-safari-http", "x-safari-https"].contains(scheme) {
                route(url)
            } else if !isMonitor && action.navigationType == .linkActivated && ["mailto", "tel"].contains(scheme) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func route(_ url: URL) {
        guard !isMonitor else { return }
        switch IncomingURLRouter.route(url) {
        case .openInApp(let mapped, let target):
            if target == tab { load(mapped) } else { onRoute?(mapped, target) }

        case .openExternal(let external):
            NSWorkspace.shared.open(external)

        case .ignore:
            break
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        route(url)
        return nil
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor ([URL]?) -> Void) {
        guard !isMonitor, let window = webView.containingWindow else {
            completionHandler(nil)
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.beginSheetModal(for: window) { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void) {
        guard !isMonitor, let window = webView.containingWindow else { completionHandler(); return }
        let alert = NSAlert()
        alert.messageText = frame.securityOrigin.host
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void) {
        guard !isMonitor, let window = webView.containingWindow else { completionHandler(false); return }
        let alert = NSAlert()
        alert.messageText = frame.securityOrigin.host
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in completionHandler(response == .alertFirstButtonReturn) }
    }
}

private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    private weak var target: DesktopWebSession?

    init(_ target: DesktopWebSession) { self.target = target }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

extension SocialTab {
    var monitorURL: URL {
        switch self {
        case .x: return URL.required(string: "https://x.com/settings")
        case .bluesky: return URL.required(string: "https://cope.works/settings")
        }
    }
}

extension NSView {
    var containingWindow: NSWindow? {
        // AppKit exposes NSView.window as unowned(unsafe). Read it synchronously
        // on the main actor, while AppKit owns the hierarchy, into a strong value.
        unsafe window
    }
}

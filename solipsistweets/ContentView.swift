//
//  ContentView.swift
//  solipsistweets
//

import Combine
import CoreMotion
import SwiftUI
import UIKit
import WebKit

struct ContentView: View {
    private let screenTimeBadgeThreshold: TimeInterval = 20 * 60
    private static let testFlightURL = URL.required(string: "https://testflight.apple.com/join/N3DtJcgD")
    @Binding var requestedURL: URL
    @State private var isLoading: Bool = true
    @State private var lastErrorDescription: String?
    @StateObject private var shakeDetector = ShakeDetector()
    @State private var showShareBanner = false
    @State private var isShareSheetPresented = false
    @State private var hideShareBannerTask: Task<Void, Never>?
    @State private var showRemoveCurrentTabConfirmation = false
    @State private var isSwitcherPressed = false
    @EnvironmentObject private var screenTimeTracker: OnScreenTimeTracker
    @Environment(\.colorScheme) private var colorScheme
    let activeTab: SocialTab
    var switcherIcon: String?
    var removableTabs: [SocialTab] = []
    var setupTabs: [SocialTab] = []
    var onSwitchTab: (() -> Void)?
    var onRemoveTab: ((SocialTab) -> Void)?
    var onSetupTab: ((SocialTab) -> Void)?

    init(
        requestedURL: Binding<URL>,
        activeTab: SocialTab,
        switcherIcon: String? = nil,
        removableTabs: [SocialTab] = [],
        setupTabs: [SocialTab] = [],
        onSwitchTab: (() -> Void)? = nil,
        onRemoveTab: ((SocialTab) -> Void)? = nil,
        onSetupTab: ((SocialTab) -> Void)? = nil
    ) {
        _requestedURL = requestedURL
        self.activeTab = activeTab
        self.switcherIcon = switcherIcon
        self.removableTabs = removableTabs
        self.setupTabs = setupTabs
        self.onSwitchTab = onSwitchTab
        self.onRemoveTab = onRemoveTab
        self.onSetupTab = onSetupTab
    }

    var body: some View {
        ZStack {
            WebView(url: requestedURL, isLoading: $isLoading, lastErrorDescription: $lastErrorDescription, activeTab: activeTab)
                .ignoresSafeArea(edges: [.bottom])

            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
            }
        }
        .overlay(alignment: .bottom) {
            if let lastErrorDescription {
                Text(lastErrorDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
                    .padding(.horizontal)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if shouldShowScreenTimeBadge {
                Text(formatDuration(screenTimeTracker.secondsToday))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(badgeForegroundColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(badgeBackgroundColor))
                    .overlay(
                        Capsule().stroke(badgeForegroundColor.opacity(0.08), lineWidth: 0.5)
                    )
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea(edges: [.bottom])
                    .onTapGesture {
                        UIControl().sendAction(#selector(NSXPCConnection.suspend),
                                               to: UIApplication.shared,
                                               for: nil)
                    }
            }
        }
        .overlay(alignment: .top) {
            if showShareBanner {
                VStack(spacing: 8) {
                    Button {
                        isShareSheetPresented = true
                        dismissShareBanner()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.subheadline.weight(.semibold))
                            Text("Share TestFlight")
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .foregroundStyle(.primary)
                        .background(.regularMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    ForEach(setupTabs) { tab in
                        Button {
                            onSetupTab?(tab)
                            dismissShareBanner()
                        } label: {
                            HStack(spacing: 8) {
                                Text(tab.emoji)
                                Text(tab.setupTitle)
                                    .font(.subheadline.weight(.semibold))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .foregroundStyle(.primary)
                            .background(.regularMaterial, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .topTrailing) {
            if let switcherIcon {
                Text(switcherIcon)
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .liquidGlass(in: Circle())
                    .scaleEffect(isSwitcherPressed ? 0.9 : 1)
                    .padding(.top, 4)
                    .padding(.trailing, 50)
                    .onTapGesture {
                        onSwitchTab?()
                    }
                    .onLongPressGesture(
                        minimumDuration: 0.7,
                        maximumDistance: 44,
                        pressing: updateSwitcherPressState,
                        perform: presentRemoveTabChoices
                    )
                    .accessibilityLabel("Switch account")
                    .accessibilityAddTraits(.isButton)
            }
        }
        .onAppear {
            shakeDetector.start()
        }
        .onDisappear {
            shakeDetector.stop()
            hideShareBannerTask?.cancel()
        }
        .onChange(of: shakeDetector.shakeCount) { _, _ in
            presentShareBanner()
        }
        .sheet(isPresented: $isShareSheetPresented) {
            ShareSheet(activityItems: [Self.testFlightURL])
        }
        .confirmationDialog("Remove a tab?", isPresented: $showRemoveCurrentTabConfirmation, titleVisibility: .visible) {
            ForEach(removeTabChoices) { tab in
                Button(tab.removeActionTitle, role: .destructive) {
                    onRemoveTab?(tab)
                }
            }
            Button("Cancel", role: .cancel) {
                showRemoveCurrentTabConfirmation = false
            }
        }
    }

    private var removeTabChoices: [SocialTab] {
        [.bluesky, .x].filter { removableTabs.contains($0) }
    }

    private var shouldShowScreenTimeBadge: Bool {
        screenTimeTracker.secondsToday >= screenTimeBadgeThreshold
    }

    private var badgeForegroundColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var badgeBackgroundColor: Color {
        colorScheme == .dark ? .black : .white
    }

    private func presentShareBanner() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            showShareBanner = true
        }
        scheduleShareBannerDismissal()
    }

    private func dismissShareBanner() {
        hideShareBannerTask?.cancel()
        hideShareBannerTask = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            showShareBanner = false
        }
    }

    private func scheduleShareBannerDismissal(after seconds: TimeInterval = 3.5) {
        hideShareBannerTask?.cancel()
        hideShareBannerTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showShareBanner = false
                }
                hideShareBannerTask = nil
            }
        }
    }

    private func updateSwitcherPressState(_ isPressing: Bool) {
        withAnimation(.spring(response: 0.18, dampingFraction: 0.72)) {
            isSwitcherPressed = isPressing
        }
    }

    private func presentRemoveTabChoices() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.bouncy(duration: 0.42, extraBounce: 0.22)) {
            isSwitcherPressed = false
        }
        showRemoveCurrentTabConfirmation = true
    }
}

private extension View {
    @ViewBuilder
    func liquidGlass<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }
}

private extension SocialTab {
    var removeActionTitle: String {
        switch self {
        case .x: return "Remove X / Twitter Tab"
        case .bluesky: return "Remove Bluesky Tab"
        }
    }
}

// MARK: - Duration formatting

private func formatDuration(_ seconds: TimeInterval) -> String {
    let totalSeconds = max(0, Int(seconds.rounded()))
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let secs = totalSeconds % 60
    let paddedMinutes = twoDigitString(minutes)
    let paddedSeconds = twoDigitString(secs)
    if hours > 0 {
        return "\(hours):\(paddedMinutes):\(paddedSeconds)"
    } else {
        return "\(minutes):\(paddedSeconds)"
    }
}

private func twoDigitString(_ value: Int) -> String {
    value < 10 ? "0\(value)" : "\(value)"
}

#Preview {
    ContentView(requestedURL: .constant(URL.required(string: "https://x.com/notifications")), activeTab: .x)
        .environmentObject(OnScreenTimeTracker())
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        _ = uiViewController
        _ = context
    }
}

final class ShakeDetector: ObservableObject {
    @Published private(set) var shakeCount: Int = 0

    private let motionManager = CMMotionManager()
    private var lastShakeAt: Date = .distantPast
    private let shakeThreshold: Double = 2.2
    private let shakeCooldown: TimeInterval = 1.0

    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }
        guard !motionManager.isDeviceMotionActive else { return }

        motionManager.deviceMotionUpdateInterval = 1.0 / 35.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let accel = motion.userAcceleration
            let magnitude = sqrt((accel.x * accel.x) + (accel.y * accel.y) + (accel.z * accel.z))
            guard magnitude >= self.shakeThreshold else { return }

            let now = Date()
            guard now.timeIntervalSince(self.lastShakeAt) >= self.shakeCooldown else { return }
            self.lastShakeAt = now
            self.shakeCount += 1
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }

    deinit {
        MainActor.assumeIsolated {
            motionManager.stopDeviceMotionUpdates()
        }
    }
}

// MARK: - WebView Wrapper

struct WebView: UIViewRepresentable {
    private static let requestTimeout: TimeInterval = 30
    let url: URL
    @Binding var isLoading: Bool
    @Binding var lastErrorDescription: String?
    let activeTab: SocialTab

    typealias UIViewType = WKWebView

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.isInspectable = true
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        context.coordinator.updateParent(self)
        context.coordinator.recordProgrammaticRequest(url)
        webView.customUserAgent = activeTab.userAgent
        load(url, in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.updateParent(self)
        guard context.coordinator.shouldApplyProgrammaticRequest(url) else { return }
        context.coordinator.recordProgrammaticRequest(url)
        load(url, in: webView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self, activeTab: activeTab)
    }

    private func load(_ url: URL, in webView: WKWebView) {
        webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: Self.requestTimeout))
    }
}

final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    private static let webSchemes: Set<String> = ["http", "https"]
    private static let safeInlineSchemes: Set<String> = ["about", "data"]

    private var parent: WebView
    private let activeTab: SocialTab
    private var didInstallContentRules: Bool = false
    private var lastProgrammaticRequestURL: URL?

    init(parent: WebView, activeTab: SocialTab) {
        self.parent = parent
        self.activeTab = activeTab
    }

    // swiftlint:disable:next implicitly_unwrapped_optional
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        DispatchQueue.main.async { [weak self] in
            self?.parent.isLoading = true
        }
    }

    // swiftlint:disable:next implicitly_unwrapped_optional
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        handleNavigationFailure(error, prefix: "Navigation failed")
    }

    // swiftlint:disable:next implicitly_unwrapped_optional
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        handleNavigationFailure(error, prefix: "Provisional navigation failed")
    }

    // swiftlint:disable:next implicitly_unwrapped_optional
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        #if DEBUG
        print("Navigation finished: \(webView.url?.absoluteString ?? "<nil>")")
        #endif

        if !didInstallContentRules {
            didInstallContentRules = true
            ContentBlocker.installRuleList(into: webView, identifier: activeTab.contentBlockerIdentifier, rulesJSON: activeTab.contentBlockerRulesJSON, completion: nil)
        }
        DispatchQueue.main.async { [weak self] in
            self?.parent.lastErrorDescription = nil
            self?.parent.isLoading = false
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
            decisionHandler(.allow)
            return
        }

        if let mapped = Self.mapSafariBounceURL(url) {
            webView.load(URLRequest(url: mapped))
            decisionHandler(.cancel)
            return
        }

        if Self.webSchemes.contains(scheme) {
            if shouldRedirectHomeTimelineToNotifications(url) {
                recordProgrammaticRequest(activeTab.startURL)
                webView.load(URLRequest(url: activeTab.startURL))
                decisionHandler(.cancel)
                return
            }
            handleHTTPNavigation(url, action: navigationAction, decisionHandler: decisionHandler)
            return
        }

        if Self.safeInlineSchemes.contains(scheme) {
            decisionHandler(.allow)
            return
        }

        if let mapped = activeTab.mapDeepLinkToHTTPS(url) {
            webView.load(URLRequest(url: mapped))
            decisionHandler(.cancel)
            return
        }

        if scheme == "echodotapp" {
            if let mapped = activeTab.mapEchoDotAppToHTTPS(url) {
                webView.load(URLRequest(url: mapped))
            }
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil else {
            return nil
        }

        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
            webView.load(navigationAction.request)
            return nil
        }

        if Self.webSchemes.contains(scheme), !isInternalHost(url) {
            Coordinator.openExternal(url)
        } else {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}

private extension Coordinator {
    func updateParent(_ parent: WebView) {
        self.parent = parent
    }

    func shouldApplyProgrammaticRequest(_ url: URL) -> Bool {
        lastProgrammaticRequestURL?.absoluteString != url.absoluteString
    }

    func recordProgrammaticRequest(_ url: URL) {
        lastProgrammaticRequestURL = url
    }

    func handleNavigationFailure(_ error: any Error, prefix: String) {
        if Self.shouldIgnoreNavigationError(error) {
            #if DEBUG
            print("Ignoring expected navigation cancellation: \(error.localizedDescription)")
            #endif
            return
        }
        #if DEBUG
        print("\(prefix): \(error.localizedDescription)")
        #endif
        DispatchQueue.main.async { [weak self] in
            self?.parent.lastErrorDescription = error.localizedDescription
            self?.parent.isLoading = false
        }
    }

    func handleHTTPNavigation(_ url: URL, action: WKNavigationAction, decisionHandler: @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        let isUserTap = action.navigationType == .linkActivated
        let isMainFrame = action.targetFrame?.isMainFrame ?? true

        guard isUserTap && isMainFrame else {
            decisionHandler(.allow)
            return
        }

        if isInternalHost(url) {
            decisionHandler(.allow)
        } else {
            Coordinator.openExternal(url)
            decisionHandler(.cancel)
        }
    }

    func isInternalHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return activeTab.canonicalHosts.contains(host)
    }

    func shouldRedirectHomeTimelineToNotifications(_ url: URL) -> Bool {
        guard isInternalHost(url) else { return false }
        let normalizedPath = Self.normalizePath(url.path)
        return normalizedPath == "/home" || normalizedPath == "/i/timeline"
    }

    static func normalizePath(_ path: String) -> String {
        let lowercased = path.lowercased()
        guard lowercased.count > 1, lowercased.hasSuffix("/") else {
            return lowercased
        }
        return String(lowercased.dropLast())
    }

    static func shouldIgnoreNavigationError(_ error: any Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return true
        }
        // WebKitErrorDomain code 102 is frame-load interrupted by a policy change.
        if nsError.domain == WKError.errorDomain,
           nsError.code == 102 {
            return true
        }
        return false
    }
}

extension Coordinator {
    static func openExternal(_ url: URL) {
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    static func mapSafariBounceURL(_ url: URL) -> URL? {
        guard let incomingScheme = url.scheme?.lowercased() else { return nil }
        let mappedScheme: String
        switch incomingScheme {
        case "x-safari-http":
            mappedScheme = "http"

        case "x-safari-https":
            mappedScheme = "https"

        default:
            return nil
        }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let host = components.host {
            var mapped = URLComponents()
            mapped.scheme = mappedScheme
            mapped.host = host
            mapped.path = components.path
            mapped.queryItems = components.queryItems
            mapped.fragment = components.fragment
            return mapped.url
        }

        let prefix = "\(incomingScheme):"
        guard url.absoluteString.lowercased().hasPrefix(prefix) else { return nil }
        let remainder = String(url.absoluteString.dropFirst(prefix.count))
        if let nestedURL = URL(string: remainder),
           let nestedScheme = nestedURL.scheme?.lowercased(),
           nestedScheme == "http" || nestedScheme == "https" {
            if nestedScheme == mappedScheme {
                return nestedURL
            }
            var nestedComponents = URLComponents(url: nestedURL, resolvingAgainstBaseURL: false)
            nestedComponents?.scheme = mappedScheme
            return nestedComponents?.url
        }
        let normalized = remainder.hasPrefix("//") ? "\(mappedScheme):\(remainder)" : "\(mappedScheme)://\(remainder)"
        return URL(string: normalized)
    }

    static func mapTwitterDeepLinkToHTTPS(url: URL) -> URL? {
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        let valueFor = { (name: String) -> String? in
            queryItems?.first(where: { $0.name.lowercased() == name })?.value
        }

        if host == "user", let screenName = valueFor("screen_name"), !screenName.isEmpty {
            return URL(string: "https://x.com/\(screenName)")
        }
        if host == "status" || host == "tweet", let id = valueFor("id"), !id.isEmpty {
            return URL(string: "https://x.com/i/web/status/\(id)")
        }
        if host == "messages" || path == "/messages" {
            return URL(string: "https://x.com/messages")
        }
        if host == "timeline" || path == "/timeline" || path == "/home" {
            return URL(string: "https://x.com/home")
        }
        if host == "search", let q = valueFor("query"), let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            return URL(string: "https://x.com/search?q=\(encoded)")
        }
        if host == "intent" || path.starts(with: "/intent/") {
            var comps = URLComponents()
            comps.scheme = "https"
            comps.host = "x.com"
            comps.path = path.isEmpty ? "/intent/tweet" : path
            comps.queryItems = queryItems
            return comps.url
        }
        return nil
    }

    static func mapEchoDotAppToHTTPS(url: URL) -> URL? {
        guard let incoming = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return URL(string: "https://x.com")
        }
        let lowerHost = incoming.host?.lowercased()
        let isXHost = lowerHost == "x.com" || lowerHost == "www.x.com" || lowerHost == "mobile.x.com"

        let pathAfterX: String
        if isXHost || lowerHost == nil {
            pathAfterX = incoming.path
        } else {
            let hostSegment = incoming.host ?? ""
            if incoming.path.hasPrefix("/") {
                pathAfterX = "/" + hostSegment + incoming.path
            } else if incoming.path.isEmpty {
                pathAfterX = "/" + hostSegment
            } else {
                pathAfterX = "/" + hostSegment + "/" + incoming.path
            }
        }

        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "x.com"
        comps.path = pathAfterX
        comps.queryItems = incoming.queryItems
        comps.fragment = incoming.fragment
        return comps.url ?? URL(string: "https://x.com")
    }
}

// MARK: - Content Blocker Management

enum ContentBlocker {
    static func installRuleList(into webView: WKWebView, identifier: String, rulesJSON: String, completion: ((Bool) -> Void)? = nil) {
        let store = WKContentRuleListStore.default()

        store?.lookUpContentRuleList(forIdentifier: identifier) { existing, error in
            if let error = error {
                #if DEBUG
                print("Rule list lookup error: \(error.localizedDescription)")
                #endif
            }
            if let existing = existing {
                webView.configuration.userContentController.add(existing)
                completion?(true)
                return
            }

            store?.compileContentRuleList(forIdentifier: identifier,
                                          encodedContentRuleList: rulesJSON) { compiled, error in
                if let error = error {
                    #if DEBUG
                    print("Rule list compile error: \(error.localizedDescription)")
                    #endif
                }
                guard let compiled = compiled else { completion?(false); return }
                webView.configuration.userContentController.add(compiled)
                completion?(true)
            }
        }
    }

    static let blueskyRulesJSON = """
    [
      {
        "trigger": { "url-filter": ".*", "if-domain": ["cope.works", "www.cope.works"] },
        "action": { "type": "css-display-none", "selector": "[data-testid='followingFeedPage']" }
      },
      {
        "trigger": { "url-filter": ".*", "if-domain": ["cope.works", "www.cope.works"] },
        "action": { "type": "css-display-none", "selector": "[aria-label='Home']" }
      },
      {
        "trigger": { "url-filter": ".*", "if-domain": ["cope.works", "www.cope.works"] },
        "action": { "type": "css-display-none", "selector": "[aria-label='Lists']" }
      },
      {
        "trigger": { "url-filter": ".*", "if-domain": ["cope.works", "www.cope.works"] },
        "action": { "type": "css-display-none", "selector": "[aria-label='Feeds']" }
      }
    ]
    """

    static let xRulesJSON = """
    [
      {
        "trigger": { "url-filter": ".*", "if-domain": ["x.com", "twitter.com"] },
        "action": { "type": "css-display-none", "selector": "[aria-label='Home']" }
      },
      {
        "trigger": { "url-filter": ".*", "if-domain": ["x.com", "twitter.com"] },
        "action": { "type": "css-display-none", "selector": "[aria-label='SuperGrok']" }
      },
      {
        "trigger": { "url-filter": ".*", "if-domain": ["x.com", "twitter.com"] },
        "action": { "type": "css-display-none", "selector": "[aria-label='Grok']" }
      },
      {
        "trigger": { "url-filter": ".*", "if-domain": ["x.com", "twitter.com"] },
        "action": { "type": "css-display-none", "selector": "[aria-label='Premium']" }
      },
      {
        "trigger": { "url-filter": ".*", "if-domain": ["x.com", "twitter.com"] },
        "action": { "type": "css-display-none", "selector": "[aria-label='Communities']" }
      },
      {
        "trigger": { "url-filter": ".*", "if-domain": ["x.com", "twitter.com"] },
        "action": { "type": "css-display-none", "selector": "[aria-label='Timeline: Your Home Timeline']" }
      },
      {
        "trigger": { "url-filter": ".*", "if-domain": ["x.com", "twitter.com"] },
        "action": { "type": "css-display-none", "selector": "[aria-label='Timeline: Explore']" }
      }
    ]
    """
}

//
//  ContentView.swift
//  solipsistweets / Orion (shared)
//

import SwiftUI
import UIKit
import WebKit

struct ContentView: View {
    private let screenTimeBadgeThreshold: TimeInterval = 20 * 60
    @Binding var requestedURL: URL
    @State private var isLoading: Bool = true
    @State private var lastErrorDescription: String? = nil
    @EnvironmentObject private var screenTimeTracker: OnScreenTimeTracker
    @Environment(\.colorScheme) private var colorScheme
    let profile: SiteProfile

    var body: some View {
        ZStack {
            WebView(url: requestedURL, isLoading: $isLoading, lastErrorDescription: $lastErrorDescription, profile: profile)
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
        .overlay(alignment: .bottom) {
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
                    .frame(maxWidth: .infinity)
                    .ignoresSafeArea(edges: [.bottom])
            }
        }
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
}

// MARK: - Duration formatting

private func formatDuration(_ seconds: TimeInterval) -> String {
    let totalSeconds = max(0, Int(seconds.rounded()))
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let secs = totalSeconds % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    } else {
        return String(format: "%d:%02d", minutes, secs)
    }
}

#Preview {
    ContentView(requestedURL: .constant(URL(string: "https://x.com/notifications")!), profile: XSiteProfile())
        .environmentObject(OnScreenTimeTracker())
}

// MARK: - WebView Wrapper

struct WebView: UIViewRepresentable {
    private static let requestTimeout: TimeInterval = 30
    let url: URL
    @Binding var isLoading: Bool
    @Binding var lastErrorDescription: String?
    let profile: SiteProfile

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
        webView.customUserAgent = profile.userAgent

        load(url, in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard webView.url?.absoluteString != url.absoluteString else { return }
        load(url, in: webView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self, profile: profile)
    }

    private func load(_ url: URL, in webView: WKWebView) {
        webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: Self.requestTimeout))
    }
}

final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    private static let webSchemes: Set<String> = ["http", "https"]
    private static let safeInlineSchemes: Set<String> = ["about", "data"]
    private static let cancelledAppBounceSchemes: Set<String> = ["x-safari-http", "x-safari-https"]

    private var parent: WebView
    private let profile: SiteProfile
    private var didInstallContentRules: Bool = false

    init(parent: WebView, profile: SiteProfile) {
        self.parent = parent
        self.profile = profile
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        DispatchQueue.main.async { [weak self] in
            self?.parent.isLoading = true
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure(error, prefix: "Navigation failed")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure(error, prefix: "Provisional navigation failed")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        #if DEBUG
        print("Navigation finished: \(webView.url?.absoluteString ?? "<nil>")")
        #endif

        if !didInstallContentRules {
            didInstallContentRules = true
            ContentBlocker.installRuleList(into: webView, identifier: profile.contentBlockerIdentifier, rulesJSON: profile.contentBlockerRulesJSON, completion: nil)
        }
        DispatchQueue.main.async { [weak self] in
            self?.parent.lastErrorDescription = nil
            self?.parent.isLoading = false
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
            decisionHandler(.allow)
            return
        }

        if Self.cancelledAppBounceSchemes.contains(scheme) {
            decisionHandler(.cancel)
            return
        }

        if Self.webSchemes.contains(scheme) {
            handleHTTPNavigation(url, action: navigationAction, decisionHandler: decisionHandler)
            return
        }

        if Self.safeInlineSchemes.contains(scheme) {
            decisionHandler(.allow)
            return
        }

        // Map custom schemes to https if profile supports it
        if let mapped = profile.mapDeepLinkToHTTPS(url) {
            webView.load(URLRequest(url: mapped))
            decisionHandler(.cancel)
            return
        }

        // echodotapp:// mapping (kept same behavior by default)
        if scheme == "echodotapp" {
            if let mapped = profile.mapEchoDotAppToHTTPS(url) {
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
    func handleNavigationFailure(_ error: Error, prefix: String) {
        #if DEBUG
        print("\(prefix): \(error.localizedDescription)")
        #endif
        DispatchQueue.main.async { [weak self] in
            self?.parent.lastErrorDescription = error.localizedDescription
            self?.parent.isLoading = false
        }
    }

    func handleHTTPNavigation(_ url: URL, action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
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
        return profile.canonicalHosts.contains(host)
    }
}

extension Coordinator {
    static func openExternal(_ url: URL) {
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    // Existing helpers kept for X profile
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
        if (host == "status" || host == "tweet"), let id = valueFor("id"), !id.isEmpty {
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

    // Keep the original X/Twitter rules available for XSiteProfile
    static let defaultRulesJSON = """
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

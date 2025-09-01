//
//  ContentView.swift
//  solipsistweets
//
//  Created by Chris Beiser on 8/31/25.
//

import SwiftUI
import UIKit
import WebKit

struct ContentView: View {
    @State private var isLoading: Bool = true
    @State private var lastErrorDescription: String? = nil

    var body: some View {
        ZStack {
            WebView(url: URL(string: "https://x.com")!, isLoading: $isLoading, lastErrorDescription: $lastErrorDescription)
                .ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
            }

            if let lastErrorDescription = lastErrorDescription {
                VStack {
                    Spacer()
                    Text(lastErrorDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)
                }
                .padding()
                .allowsHitTesting(false)
            }
        }
    }
}

#Preview {
    ContentView()
}

// MARK: - WebView Wrapper

struct WebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var lastErrorDescription: String?
    typealias UIViewType = WKWebView

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default() // persistent cookies and storage
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptEnabled = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.customUserAgent = Coordinator.safariLikeUserAgent

        // Load requested URL first (don't mutate SwiftUI state here)
        webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // No-op: avoid interrupting provisional loads
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
}

final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    private var parent: WebView
    private var didApplyNonHTTPSFallback: Bool = false
    private var didInstallContentRules: Bool = false
    private var didPerformExternalRedirectFallback: Bool = false

    init(parent: WebView) {
        self.parent = parent
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        DispatchQueue.main.async { [weak self] in
            self?.parent.isLoading = true
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        #if DEBUG
        print("Navigation failed: \(error.localizedDescription)")
        #endif
        DispatchQueue.main.async { [weak self] in
            self?.parent.lastErrorDescription = error.localizedDescription
            self?.parent.isLoading = false
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        #if DEBUG
        print("Provisional navigation failed: \(error.localizedDescription)")
        #endif
        DispatchQueue.main.async { [weak self] in
            self?.parent.lastErrorDescription = error.localizedDescription
            self?.parent.isLoading = false
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        #if DEBUG
        print("Navigation finished: \(webView.url?.absoluteString ?? "<nil>")")
        #endif
        if !didInstallContentRules {
            didInstallContentRules = true
            ContentBlocker.installRuleList(into: webView, completion: nil)
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

        // Cancel x-safari-* app-bounce attempts to avoid reload loops
        if scheme == "x-safari-http" || scheme == "x-safari-https" {
            decisionHandler(.cancel)
            return
        }

        // Allow standard web/content schemes
        if scheme == "http" || scheme == "https" || scheme == "about" || scheme == "data" {
            decisionHandler(.allow)
            return
        }

        // Handle twitter:// or x:// deep links by mapping to https once
        if scheme == "twitter" || scheme == "x" {
            if let url = navigationAction.request.url,
               let mapped = Coordinator.mapTwitterDeepLinkToHTTPS(url: url) {
                webView.load(URLRequest(url: mapped))
            } else if !didPerformExternalRedirectFallback {
                didPerformExternalRedirectFallback = true
                webView.load(URLRequest(url: URL(string: "https://x.com")!))
            }
            decisionHandler(.cancel)
            return
        }

        // Allow all other schemes (no external open here to keep things simple)
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Open target=_blank links in the same webView
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // Recover from WebContent process crashes by reloading
        webView.reload()
    }
}

extension Coordinator {
    static var safariLikeUserAgent: String {
        // Modern iPhone Safari UA
        return "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
    }
    // Best-effort mapping from twitter:// or x:// deep links to web URLs on x.com
    static func mapTwitterDeepLinkToHTTPS(url: URL) -> URL? {
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        let valueFor = { (name: String) -> String? in
            queryItems?.first(where: { $0.name.lowercased() == name })?.value
        }

        // Common patterns
        // twitter://user?screen_name=username
        if host == "user", let screenName = valueFor("screen_name"), !screenName.isEmpty {
            return URL(string: "https://x.com/\(screenName)")
        }

        // twitter://status?id=123 or twitter://tweet?id=123
        if (host == "status" || host == "tweet"), let id = valueFor("id"), !id.isEmpty {
            return URL(string: "https://x.com/i/web/status/\(id)")
        }

        // twitter://messages -> DMs
        if host == "messages" || path == "/messages" {
            return URL(string: "https://x.com/messages")
        }

        // twitter://timeline -> home
        if host == "timeline" || path == "/timeline" || path == "/home" {
            return URL(string: "https://x.com/home")
        }

        // twitter://search?query=...
        if host == "search", let q = valueFor("query"), let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            return URL(string: "https://x.com/search?q=\(encoded)")
        }

        // twitter://intent/tweet?... or x://intent/tweet
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
}

// MARK: - Content Blocker Management

enum ContentBlocker {
    private static let ruleListIdentifier = "com.solipsistweets.ContentBlocker.rules"

    static func installRuleList(into webView: WKWebView, completion: ((Bool) -> Void)? = nil) {
        let store = WKContentRuleListStore.default()

        store?.lookUpContentRuleList(forIdentifier: ruleListIdentifier) { existing, error in
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

            store?.compileContentRuleList(forIdentifier: ruleListIdentifier,
                                          encodedContentRuleList: defaultRulesJSON) { compiled, error in
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

    // Default content blocking rules for x.com/twitter.com.
    // You can extend the selectors and rules below as needed.
    private static let defaultRulesJSON = """
    [
      {
        "trigger": {
          "url-filter": ".*",
          "if-domain": ["x.com", "twitter.com"]
        },
        "action": {
          "type": "css-display-none",
          "selector": "aside[aria-label='Who to follow'], section[aria-label^='Timeline: Trending'], [data-testid='sidebarColumn']"
        }
      },
      {
        "trigger": {
          "url-filter": ".*/i/premium.*",
          "if-domain": ["x.com", "twitter.com"]
        },
        "action": { "type": "block" }
      }
    ]
    """
}

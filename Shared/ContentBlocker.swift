import Foundation
import WebKit

// MARK: - Content Blocker Management

enum ContentBlocker {
    static func installRuleList(into webView: WKWebView, identifier: String, rulesJSON: String, completion: ((Bool) -> Void)? = nil) {
        guard let store = WKContentRuleListStore.default() else {
            completion?(false)
            return
        }

        store.lookUpContentRuleList(forIdentifier: identifier) { [weak webView] existing, error in
            guard let webView else { completion?(false); return }
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

            store.compileContentRuleList(forIdentifier: identifier,
                                         encodedContentRuleList: rulesJSON) { [weak webView] compiled, error in
                if let error = error {
                    #if DEBUG
                    print("Rule list compile error: \(error.localizedDescription)")
                    #endif
                }
                guard let compiled, let webView else { completion?(false); return }
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

import Foundation
import WebKit

private enum SharedUserAgent {
    static let mobileSafari17_5 = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
}

protocol SiteProfile {
    // Hosts that are considered “internal” and should open in-app
    var canonicalHosts: Set<String> { get }
    // Initial URL to load
    var startURL: URL { get }
    // Optional override for WebKit user agent string
    var userAgent: String { get }
    // Optional deep link mapping from custom schemes to https
    func mapDeepLinkToHTTPS(_ url: URL) -> URL?
    // Optional mapping for custom echodotapp://. Keep behavior same across profiles unless overridden.
    func mapEchoDotAppToHTTPS(_ url: URL) -> URL?
    // Content blocker identifier and JSON list
    var contentBlockerIdentifier: String { get }
    var contentBlockerRulesJSON: String { get }
}

struct XSiteProfile: SiteProfile {
    let canonicalHosts: Set<String> = ["x.com", "www.x.com", "mobile.x.com", "twitter.com", "www.twitter.com"]
    var startURL: URL { URL(string: "https://x.com/notifications")! }
    var userAgent: String { SharedUserAgent.mobileSafari17_5 }
    func mapDeepLinkToHTTPS(_ url: URL) -> URL? {
        Coordinator.mapTwitterDeepLinkToHTTPS(url: url)
    }
    func mapEchoDotAppToHTTPS(_ url: URL) -> URL? { Coordinator.mapEchoDotAppToHTTPS(url: url) }
    var contentBlockerIdentifier: String { "com.solipsistweets.ContentBlocker.rules.v11" }
    var contentBlockerRulesJSON: String { ContentBlocker.defaultRulesJSON }
}

struct RedditSiteProfile: SiteProfile {
    let canonicalHosts: Set<String> = ["reddit.com", "www.reddit.com", "old.reddit.com", "m.reddit.com"]
    var startURL: URL { URL(string: "https://www.reddit.com/")! }
    var userAgent: String { SharedUserAgent.mobileSafari17_5 }
    func mapDeepLinkToHTTPS(_ url: URL) -> URL? {
        // No known reddit:// scheme mapping needed; return nil to cancel deep links
        return nil
    }
    func mapEchoDotAppToHTTPS(_ url: URL) -> URL? { Coordinator.mapEchoDotAppToHTTPS(url: url) }
    var contentBlockerIdentifier: String { "com.orion.ContentBlocker.rules.v17" }
    var contentBlockerRulesJSON: String { Self.redditRulesJSON }

    private static let redditRulesJSON = """
    [
      {
        "trigger": {
          "url-filter": ".*"
        },
        "action": {
          "type": "css-display-none",
          "selector": "#main-content"
        }
      }
    ]
    """
}

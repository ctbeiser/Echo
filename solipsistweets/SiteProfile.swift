import Foundation
import WebKit
import UIKit

private enum SharedUserAgent {
    static var mobileSafariCurrentDevice: String {
        let osVersion = UIDevice.current.systemVersion
        let osToken = osTokenForUserAgent(from: osVersion)
        let safariVersion = safariVersion(from: osVersion)
        return "Mozilla/5.0 (iPhone; CPU iPhone OS \(osToken) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(safariVersion) Mobile/15E148 Safari/604.1"
    }

    private static func osTokenForUserAgent(from osVersion: String) -> String {
        let components = osVersion.split(separator: ".")
        let major = Int(components.first ?? "0") ?? 0

        // iOS 26+ freezes the OS token in UA to the final pre-iOS-26 value.
        if major >= 26 {
            return "18_6"
        }
        return osVersion.replacingOccurrences(of: ".", with: "_")
    }

    private static func safariVersion(from osVersion: String) -> String {
        let components = osVersion.split(separator: ".")
        guard let major = components.first else { return "18.0" }
        let minor = components.count > 1 ? components[1] : "0"
        return "\(major).\(minor)"
    }
}

protocol SiteProfile {
    // Hosts that are considered “internal” and should open in-app
    var canonicalHosts: Set<String> { get }
    // Initial URL to load
    var startURL: URL { get }
    // User agent string used for all requests.
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
    var userAgent: String { SharedUserAgent.mobileSafariCurrentDevice }
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
    var userAgent: String { SharedUserAgent.mobileSafariCurrentDevice }
    func mapDeepLinkToHTTPS(_ url: URL) -> URL? {
        // No known reddit:// scheme mapping needed; return nil to cancel deep links
        return nil
    }
    func mapEchoDotAppToHTTPS(_ url: URL) -> URL? {
        guard let incoming = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return URL(string: "https://www.reddit.com")
        }
        let lowerHost = incoming.host?.lowercased()
        let isRedditHost = canonicalHosts.contains(lowerHost ?? "")

        let path: String
        if isRedditHost || lowerHost == nil {
            path = incoming.path
        } else {
            let hostSegment = incoming.host ?? ""
            if incoming.path.hasPrefix("/") {
                path = "/" + hostSegment + incoming.path
            } else if incoming.path.isEmpty {
                path = "/" + hostSegment
            } else {
                path = "/" + hostSegment + "/" + incoming.path
            }
        }

        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "www.reddit.com"
        comps.path = path
        comps.queryItems = incoming.queryItems
        comps.fragment = incoming.fragment
        return comps.url ?? URL(string: "https://www.reddit.com")
    }
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

import Foundation
import UIKit
import WebKit

extension URL {
    static func required(string: String) -> URL {
        guard let url = URL(string: string) else {
            fatalError("Invalid required URL: \(string)")
        }
        return url
    }
}

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

enum SocialTab: String, CaseIterable, Identifiable {
    case x
    case bluesky

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .x: return "Twitter / X"
        case .bluesky: return "Bluesky"
        }
    }

    var setupTitle: String {
        switch self {
        case .x: return "Set Up X"
        case .bluesky: return "Set Up Bluesky"
        }
    }

    var emoji: String {
        switch self {
        case .x: return "🐦"
        case .bluesky: return "🦋"
        }
    }

    var canonicalHosts: Set<String> {
        switch self {
        case .x: return ["x.com", "www.x.com", "mobile.x.com", "twitter.com", "www.twitter.com"]
        case .bluesky: return ["cope.works", "www.cope.works"]
        }
    }

    var startURL: URL {
        switch self {
        case .x: return URL.required(string: "https://x.com/notifications")
        case .bluesky: return URL.required(string: "https://cope.works/notifications")
        }
    }

    var userAgent: String {
        SharedUserAgent.mobileSafariCurrentDevice
    }

    var contentBlockerIdentifier: String {
        switch self {
        case .x: return "com.solipsistweets.ContentBlocker.rules.v11"
        case .bluesky: return "com.solipsistweets.ContentBlocker.bluesky.rules.v4"
        }
    }

    var contentBlockerRulesJSON: String {
        switch self {
        case .x: return ContentBlocker.xRulesJSON
        case .bluesky: return ContentBlocker.blueskyRulesJSON
        }
    }

    func mapDeepLinkToHTTPS(_ url: URL) -> URL? {
        switch self {
        case .x: return Coordinator.mapTwitterDeepLinkToHTTPS(url: url)
        case .bluesky: return nil
        }
    }

    func mapEchoDotAppToHTTPS(_ url: URL) -> URL? {
        switch self {
        case .x: return Coordinator.mapEchoDotAppToHTTPS(url: url)
        case .bluesky: return nil
        }
    }
}

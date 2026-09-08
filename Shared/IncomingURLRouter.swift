//
//  IncomingURLRouter.swift
//  solipsistweets
//

import Foundation

enum EchoURLScheme {
    static let appSchemes: Set<String> = ["echodotapp", "e"]

    static func isAppScheme(_ scheme: String?) -> Bool {
        guard let scheme else { return false }
        return appSchemes.contains(scheme.lowercased())
    }
}

enum IncomingURLRoute {
    case openInApp(URL, SocialTab)
    case openExternal(URL)
    case ignore
}

enum IncomingURLRouter {
    private static let webSchemes: Set<String> = ["http", "https"]
    private static let safariBounceSchemes: [String: String] = [
        "x-safari-http": "http",
        "x-safari-https": "https"
    ]
    private static let xHosts: Set<String> = [
        "x.com",
        "www.x.com",
        "mobile.x.com",
        "twitter.com",
        "www.twitter.com",
        "mobile.twitter.com"
    ]
    private static let blueskyHosts: Set<String> = [
        "bsky.app",
        "www.bsky.app",
        "cope.works",
        "www.cope.works"
    ]

    static func route(_ url: URL) -> IncomingURLRoute {
        guard let scheme = url.scheme?.lowercased() else { return .ignore }

        if EchoURLScheme.appSchemes.contains(scheme) {
            return routeAppScheme(url)
        }

        if webSchemes.contains(scheme) {
            return routeWebURL(url)
        }

        if let mapped = mapSafariBounceURL(url) {
            return routeWebURL(mapped)
        }

        if let mapped = mapTwitterDeepLinkToHTTPS(url: url) {
            return .openInApp(mapped, .x)
        }

        return .ignore
    }

    static func mapSafariBounceURL(_ url: URL) -> URL? {
        guard let incomingScheme = url.scheme?.lowercased(),
              let mappedScheme = safariBounceSchemes[incomingScheme] else {
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
           webSchemes.contains(nestedScheme) {
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
        if case .openInApp(let mapped, _) = routeAppScheme(url) {
            return mapped
        }
        return nil
    }

    private static func routeWebURL(_ url: URL) -> IncomingURLRoute {
        if let mapped = canonicalXWebURL(from: url) {
            return .openInApp(mapped, .x)
        }

        if let mapped = canonicalBlueskyWebURL(from: url) {
            return .openInApp(mapped, .bluesky)
        }

        return .openExternal(url)
    }

    private static func routeAppScheme(_ url: URL) -> IncomingURLRoute {
        if let nestedURL = nestedURL(from: url) {
            return routeWebURL(nestedURL)
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .openInApp(URL.required(string: "https://x.com"), .x)
        }

        let lowerHost = components.host?.lowercased()
        if let lowerHost, xHosts.contains(lowerHost) || blueskyHosts.contains(lowerHost) {
            return routeWebURL(webURL(from: components, host: lowerHost))
        }

        if let lowerHost, lowerHost.contains(".") {
            return .openExternal(webURL(from: components, host: lowerHost))
        }

        return .openInApp(xURL(fromAppSchemeComponents: components), .x)
    }

    private static func nestedURL(from url: URL) -> URL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        if let queryItems = components.queryItems {
            for name in ["url", "u", "target"] {
                if let value = queryItems.first(where: { $0.name.lowercased() == name })?.value,
                   let nestedURL = URL(string: value),
                   let nestedScheme = nestedURL.scheme?.lowercased(),
                   webSchemes.contains(nestedScheme) {
                    return nestedURL
                }
            }
        }

        guard let scheme = url.scheme else { return nil }
        let prefix = "\(scheme):"
        let remainder = String(url.absoluteString.dropFirst(prefix.count))
        guard let nestedURL = URL(string: remainder),
              let nestedScheme = nestedURL.scheme?.lowercased(),
              webSchemes.contains(nestedScheme) else {
            return nil
        }
        return nestedURL
    }

    private static func canonicalXWebURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              xHosts.contains(host),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = "https"
        components.host = "x.com"
        return components.url
    }

    private static func canonicalBlueskyWebURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              blueskyHosts.contains(host),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = "https"
        components.host = "cope.works"
        return components.url
    }

    private static func webURL(from components: URLComponents, host: String) -> URL {
        var mapped = URLComponents()
        mapped.scheme = "https"
        mapped.host = host
        mapped.path = components.path
        mapped.queryItems = components.queryItems
        mapped.fragment = components.fragment
        return mapped.url ?? URL.required(string: "https://\(host)")
    }

    private static func xURL(fromAppSchemeComponents components: URLComponents) -> URL {
        let path: String
        if let host = components.host, !host.isEmpty {
            if components.path.hasPrefix("/") {
                path = "/" + host + components.path
            } else if components.path.isEmpty {
                path = "/" + host
            } else {
                path = "/" + host + "/" + components.path
            }
        } else {
            path = components.path
        }

        var mapped = URLComponents()
        mapped.scheme = "https"
        mapped.host = "x.com"
        mapped.path = path.isEmpty ? "/" : path
        mapped.queryItems = components.queryItems
        mapped.fragment = components.fragment
        return mapped.url ?? URL.required(string: "https://x.com")
    }
}

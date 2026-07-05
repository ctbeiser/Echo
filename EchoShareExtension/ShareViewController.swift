//
//  ShareViewController.swift
//  EchoShareExtension
//

import Foundation
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private var didBeginRouting = false

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.startAnimating()
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        beginRoutingIfNeeded()
    }

    private func beginRoutingIfNeeded() {
        guard !didBeginRouting else { return }
        didBeginRouting = true

        let providers = itemProviders()
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(SharedURLItemParser.urlTypeIdentifier) }) {
            loadURL(from: provider, typeIdentifier: SharedURLItemParser.urlTypeIdentifier)
            return
        }

        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(SharedURLItemParser.plainTextTypeIdentifier) }) {
            loadURL(from: provider, typeIdentifier: SharedURLItemParser.plainTextTypeIdentifier)
            return
        }

        finishWithCancellation()
    }

    private func itemProviders() -> [NSItemProvider] {
        extensionContext?.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] } ?? []
    }

    private func loadURL(from provider: NSItemProvider, typeIdentifier: String) {
        provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { [weak self] item, _ in
            let url = SharedURLItemParser.url(from: item)
            DispatchQueue.main.async { [weak self] in
                self?.routeLoadedURL(url)
            }
        }
    }

    private func routeLoadedURL(_ sharedURL: URL?) {
        guard let sharedURL else {
            finishWithCancellation()
            return
        }

        let targetURL = ShareURLRouter.routedURL(for: sharedURL)
        extensionContext?.open(targetURL) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            }
        }
    }

    private func finishWithCancellation() {
        let error = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil)
        extensionContext?.cancelRequest(withError: error)
    }
}

private enum SharedURLItemParser {
    nonisolated static let urlTypeIdentifier = UTType.url.identifier
    nonisolated static let plainTextTypeIdentifier = UTType.plainText.identifier

    nonisolated static func url(from item: (any NSSecureCoding)?) -> URL? {
        if let url = item as? URL {
            return url
        }

        if let string = item as? String {
            return firstURL(in: string)
        }

        if let data = item as? Data,
           let string = String(data: data, encoding: .utf8) {
            return firstURL(in: string)
        }

        return nil
    }

    nonisolated private static func firstURL(in string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        return detector.firstMatch(in: trimmed, options: [], range: range)?.url
    }
}

private enum ShareURLRouter {
    nonisolated private static let xHosts: Set<String> = [
        "x.com",
        "www.x.com",
        "mobile.x.com",
        "twitter.com",
        "www.twitter.com",
        "mobile.twitter.com"
    ]
    nonisolated private static let blueskyHosts: Set<String> = [
        "bsky.app",
        "www.bsky.app",
        "cope.works",
        "www.cope.works"
    ]

    nonisolated static func routedURL(for sharedURL: URL) -> URL {
        guard let canonicalURL = canonicalEchoURL(from: sharedURL) else {
            return sharedURL
        }

        var components = URLComponents()
        components.scheme = "echodotapp"
        components.host = "open"
        components.queryItems = [
            URLQueryItem(name: "url", value: canonicalURL.absoluteString)
        ]
        return components.url ?? sharedURL
    }

    nonisolated private static func canonicalEchoURL(from url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.scheme = "https"

        if xHosts.contains(host) {
            components.host = "x.com"
        } else if blueskyHosts.contains(host) {
            components.host = "cope.works"
        } else {
            return nil
        }

        return components.url
    }
}

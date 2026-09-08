import AppKit
import Foundation

enum DesktopUserAgent {
    static var safariApplicationName: String { "Version/\(safariVersion) Safari/605.1.15" }

    static var mobileSafari: String {
        // Safari freezes the iPhone OS token at 18_7; its product version
        // continues to track releases. Keep the standard mobile Safari format.
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(safariVersion) Mobile/15E148 Safari/604.1"
    }

    private static let safariVersion: String = {
        let safariURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari")
        let version = safariURL.flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String }
        let parts = version?.split(separator: ".") ?? []
        let isNumericVersion = parts.count >= 2 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }
        return isNumericVersion ? parts.prefix(2).joined(separator: ".") : fallbackVersion
    }()

    private static var fallbackVersion: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        // macOS 14/15 shipped Safari 17/18; the versions align from macOS 26.
        return "\(os.majorVersion >= 26 ? os.majorVersion : os.majorVersion + 3).0"
    }
}

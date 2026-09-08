import Foundation

enum NotificationScript {
    static let handlerName = "echoNotificationCount"

    static func source(for tab: SocialTab) -> String {
        guard let url = Bundle.main.url(forResource: "NotificationObserver", withExtension: "js"),
              let script = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("Missing required NotificationObserver.js resource")
        }
        return "(() => { const service = '\(tab.rawValue)';\n" + script + "\n})();"
    }
}

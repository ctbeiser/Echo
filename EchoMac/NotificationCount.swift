import Foundation

struct NotificationCount: Equatable {
    let value: Int
    let isLowerBound: Bool

    var label: String { "\(value)\(isLowerBound ? "+" : "")" }
}

enum NotificationStatus: Equatable {
    case checking
    case current(NotificationCount, Date)
    case viewed(Date)
    case unavailable(String)
    case rateLimited(Date)

    var count: NotificationCount? {
        switch self {
        case .current(let count, _): return count
        case .viewed: return NotificationCount(value: 0, isLowerBound: false)
        case .checking, .unavailable, .rateLimited: return nil
        }
    }

    var updatedAt: Date? {
        switch self {
        case .current(_, let date), .viewed(let date): return date
        case .checking, .unavailable, .rateLimited: return nil
        }
    }

    var description: String {
        switch self {
        case .checking: return "Notification count not available yet"
        case .current(let count, _): return "\(count.label) unread notifications"
        case .viewed: return "Notifications viewed in Echo"
        case .unavailable(let reason): return reason
        case .rateLimited: return "Waiting before checking again"
        }
    }
}

// JavaScript sends only this boundary model; credentials stay in WebKit.
struct NotificationReport: Decodable {
    enum State: String, Decodable {
        case count
        case signedOut
        case unavailable
        case rateLimited
    }

    let state: State
    let count: Int?
    let lowerBound: Bool?
    let retryAfterSeconds: Int?

    var status: NotificationStatus? {
        switch state {
        case .count:
            guard let count, (0...1_000_000).contains(count), let lowerBound else { return nil }
            return .current(NotificationCount(value: count, isLowerBound: lowerBound), Date())

        case .signedOut:
            return .unavailable("Open this account to finish signing in")

        case .unavailable:
            return .unavailable("Count unavailable — refresh to retry")

        case .rateLimited:
            guard let retryAfterSeconds, (1...31_536_000).contains(retryAfterSeconds) else { return nil }
            return .rateLimited(Date().addingTimeInterval(TimeInterval(retryAfterSeconds)))
        }
    }
}

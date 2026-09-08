import Foundation

enum BackgroundCountPolicy {
    static func initialDelay(for tab: SocialTab) -> TimeInterval {
        switch tab {
        case .x: return .random(in: 30...90)
        case .bluesky: return .random(in: 3...10)
        }
    }

    static func interval(for tab: SocialTab) -> TimeInterval {
        switch tab {
        case .x: return .random(in: 5 * 60...9 * 60)
        case .bluesky: return .random(in: 60...90)
        }
    }

    static func freshnessLimit(for tab: SocialTab) -> TimeInterval {
        switch tab {
        case .x: return 12 * 60
        case .bluesky: return 4 * 60
        }
    }

    static func minimumRefreshGap(for tab: SocialTab) -> TimeInterval {
        switch tab {
        case .x: return 5 * 60
        case .bluesky: return 60
        }
    }
}

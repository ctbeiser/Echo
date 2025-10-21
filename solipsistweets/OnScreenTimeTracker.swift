import Foundation
import Combine

final class OnScreenTimeTracker: ObservableObject {
    @Published var secondsToday: TimeInterval = 0
    private var timer: Timer?
    private var lastTickDate: Date?
    private let userDefaults: UserDefaults
    private let calendar: Calendar

    init(userDefaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.userDefaults = userDefaults
        self.calendar = calendar
        self.secondsToday = userDefaults.double(forKey: Self.key(for: Date()))
    }

    deinit {
        timer?.invalidate()
    }

    func start() {
        guard timer == nil else { return }
        // Refresh in case day changed while inactive
        secondsToday = userDefaults.double(forKey: Self.key(for: Date()))
        lastTickDate = Date()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopAndFlush() {
        guard let last = lastTickDate else {
            invalidateTimer()
            return
        }
        let now = Date()
        accumulate(from: last, to: now)
        invalidateTimer()
    }

    private func invalidateTimer() {
        timer?.invalidate()
        timer = nil
        lastTickDate = nil
    }

    private func tick() {
        let now = Date()
        if let last = lastTickDate {
            accumulate(from: last, to: now)
        }
        lastTickDate = now
    }

    private func accumulate(from start: Date, to end: Date) {
        guard end > start else { return }
        if calendar.isDate(start, inSameDayAs: end) {
            let seconds = end.timeIntervalSince(start)
            add(seconds: seconds, for: end)
            return
        }

        var cursor = start
        while !calendar.isDate(cursor, inSameDayAs: end) {
            guard let nextMidnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: cursor)) else { break }
            let secondsUntilMidnight = nextMidnight.timeIntervalSince(cursor)
            add(seconds: secondsUntilMidnight, for: cursor)
            cursor = nextMidnight
        }
        let remaining = end.timeIntervalSince(cursor)
        add(seconds: remaining, for: end)
    }

    private func add(seconds: TimeInterval, for date: Date) {
        let key = Self.key(for: date)
        let existing = userDefaults.double(forKey: key)
        userDefaults.set(existing + seconds, forKey: key)
        if calendar.isDateInToday(date) {
            secondsToday = userDefaults.double(forKey: key)
        }
    }

    static func key(for date: Date) -> String {
        return "onScreenSeconds_" + Self.dayString(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    private static func dayString(from date: Date) -> String {
        return dayFormatter.string(from: date)
    }
}

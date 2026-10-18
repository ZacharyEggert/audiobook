import Foundation

/// One stretch of listening: when it began, the wall-clock time it took and the book time it covered.
public struct ListeningEntry: Equatable, Sendable {
    public var start: Date
    /// Wall-clock seconds spent listening.
    public var real: TimeInterval
    /// Seconds of book played; more than `real` when listening faster than 1×.
    public var content: TimeInterval

    public init(start: Date, real: TimeInterval, content: TimeInterval) {
        self.start = start
        self.real = real
        self.content = content
    }
}

public struct ListeningTotals: Equatable, Sendable {
    public var real: TimeInterval = 0
    public var content: TimeInterval = 0

    public init(real: TimeInterval = 0, content: TimeInterval = 0) {
        self.real = real
        self.content = content
    }

    /// Time saved by listening faster than 1×.
    public var saved: TimeInterval {
        max(content - real, 0)
    }
}

public struct ListeningBucket: Equatable, Sendable {
    /// The first instant of the day or week.
    public var start: Date
    public var totals: ListeningTotals
}

/// Listening totals per local day (PLAN §5 Stats). Days follow `calendar`, so its time zone decides where midnight falls;
/// an entry that crosses midnight is split between the days, its book time in proportion.
public struct ListeningStats: Sendable {
    private let calendar: Calendar
    /// Keyed by the day's start.
    private let days: [Date: ListeningTotals]

    public init(entries: [ListeningEntry], calendar: Calendar = .current) {
        self.calendar = calendar
        var days: [Date: ListeningTotals] = [:]
        for entry in entries where entry.real > 0 {
            let end = entry.start.addingTimeInterval(entry.real)
            var cursor = entry.start
            while cursor < end {
                let day = calendar.startOfDay(for: cursor)
                let next = calendar.date(byAdding: .day, value: 1, to: day) ?? end
                let sliceEnd = min(max(next, cursor.addingTimeInterval(1)), end)
                let slice = sliceEnd.timeIntervalSince(cursor)
                days[day, default: ListeningTotals()].real += slice
                days[day, default: ListeningTotals()].content += entry.content * slice / entry.real
                cursor = sliceEnd
            }
        }
        self.days = days
    }

    public var total: ListeningTotals {
        days.values.reduce(into: ListeningTotals()) {
            $0.real += $1.real
            $0.content += $1.content
        }
    }

    /// Consecutive days with listening up to `now`. Today needn't have any yet, so the streak survives until midnight.
    public func streak(asOf now: Date) -> Int {
        let today = calendar.startOfDay(for: now)
        var day = days[today] == nil ? calendar.date(byAdding: .day, value: -1, to: today) : today
        var count = 0
        while let current = day, days[current] != nil {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: current)
        }
        return count
    }

    /// The last `count` days, oldest first, ending with the day of `now`. Days without listening are zero.
    public func daily(count: Int, endingAt now: Date) -> [ListeningBucket] {
        let today = calendar.startOfDay(for: now)
        return (0 ..< max(count, 0)).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map { ListeningBucket(start: $0, totals: days[$0] ?? .init()) }
        }
    }

    /// The last `count` weeks, oldest first, ending with the week of `now`. Weeks start where `calendar` says.
    public func weekly(count: Int, endingAt now: Date) -> [ListeningBucket] {
        var byWeek: [Date: ListeningTotals] = [:]
        for (day, totals) in days {
            guard let week = calendar.dateInterval(of: .weekOfYear, for: day)?.start else { continue }
            byWeek[week, default: ListeningTotals()].real += totals.real
            byWeek[week, default: ListeningTotals()].content += totals.content
        }
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        return (0 ..< max(count, 0)).reversed().compactMap { offset in
            calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeek).map {
                ListeningBucket(start: $0, totals: byWeek[$0] ?? .init())
            }
        }
    }
}

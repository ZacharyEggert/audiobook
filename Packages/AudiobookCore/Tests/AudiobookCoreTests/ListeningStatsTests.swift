import AudiobookCore
import Foundation
import Testing

private func calendar(_ zone: String, firstWeekday: Int = 2) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    calendar.firstWeekday = firstWeekday
    return calendar
}

private func date(_ string: String) -> Date {
    ISO8601DateFormatter().date(from: string)!
}

private let utc = calendar("UTC")

@Test func `totals add up and time saved is book time minus real time`() {
    let stats = ListeningStats(entries: [
        ListeningEntry(start: date("2026-03-02T10:00:00Z"), real: 3600, content: 5400),
        ListeningEntry(start: date("2026-03-03T10:00:00Z"), real: 600, content: 600),
    ], calendar: utc)
    #expect(stats.total == ListeningTotals(real: 4200, content: 6000))
    #expect(stats.total.saved == 1800)
}

@Test func `slower than real time saves nothing`() {
    #expect(ListeningTotals(real: 100, content: 50).saved == 0)
}

@Test func `an entry across midnight splits between days in proportion`() {
    let stats = ListeningStats(
        entries: [ListeningEntry(start: date("2026-03-02T23:30:00Z"), real: 3600, content: 7200)],
        calendar: utc,
    )
    let days = stats.daily(count: 2, endingAt: date("2026-03-03T12:00:00Z"))
    #expect(days.map(\.totals) == [ListeningTotals(real: 1800, content: 3600), ListeningTotals(real: 1800, content: 3600)])
}

@Test func `the time zone decides which day a session falls on`() {
    let entry = ListeningEntry(start: date("2026-03-02T23:00:00Z"), real: 600, content: 600)
    let now = date("2026-03-03T12:00:00Z")
    // 23:00 UTC is still 15:00 on Mar 2 in Los Angeles, but 08:00 on Mar 3 in Tokyo.
    let losAngeles = ListeningStats(entries: [entry], calendar: calendar("America/Los_Angeles")).daily(count: 2, endingAt: now)
    let tokyo = ListeningStats(entries: [entry], calendar: calendar("Asia/Tokyo")).daily(count: 2, endingAt: now)
    #expect(losAngeles.map(\.totals.real) == [600, 0])
    #expect(tokyo.map(\.totals.real) == [0, 600])
}

@Test func `daily buckets are contiguous, oldest first, with empty days as zero`() {
    let stats = ListeningStats(
        entries: [ListeningEntry(start: date("2026-03-01T09:00:00Z"), real: 60, content: 60)],
        calendar: utc,
    )
    let days = stats.daily(count: 3, endingAt: date("2026-03-03T18:00:00Z"))
    #expect(days.map(\.start) == [date("2026-03-01T00:00:00Z"), date("2026-03-02T00:00:00Z"), date("2026-03-03T00:00:00Z")])
    #expect(days.map(\.totals.real) == [60, 0, 0])
}

@Test func `weekly buckets follow the calendar's first weekday`() {
    // Sunday Mar 1 and Monday Mar 2, 2026.
    let entries = [
        ListeningEntry(start: date("2026-03-01T10:00:00Z"), real: 100, content: 100),
        ListeningEntry(start: date("2026-03-02T10:00:00Z"), real: 200, content: 200),
    ]
    let now = date("2026-03-04T10:00:00Z")
    let monday = ListeningStats(entries: entries, calendar: calendar("UTC", firstWeekday: 2)).weekly(count: 2, endingAt: now)
    #expect(monday.map(\.start) == [date("2026-02-23T00:00:00Z"), date("2026-03-02T00:00:00Z")])
    #expect(monday.map(\.totals.real) == [100, 200])
    let sunday = ListeningStats(entries: entries, calendar: calendar("UTC", firstWeekday: 1)).weekly(count: 2, endingAt: now)
    #expect(sunday.map(\.totals.real) == [0, 300])
}

@Test func `streak counts consecutive days ending today`() {
    let entries = ["2026-03-03", "2026-03-04", "2026-03-05", "2026-03-01"].map {
        ListeningEntry(start: date("\($0)T12:00:00Z"), real: 60, content: 60)
    }
    let stats = ListeningStats(entries: entries, calendar: utc)
    #expect(stats.streak(asOf: date("2026-03-05T20:00:00Z")) == 3)
}

@Test func `streak survives a day with nothing yet but not two`() {
    let stats = ListeningStats(
        entries: [ListeningEntry(start: date("2026-03-04T12:00:00Z"), real: 60, content: 60)],
        calendar: utc,
    )
    #expect(stats.streak(asOf: date("2026-03-05T08:00:00Z")) == 1)
    #expect(stats.streak(asOf: date("2026-03-06T08:00:00Z")) == 0)
}

@Test func `streak counts days across a daylight saving change`() {
    let losAngeles = calendar("America/Los_Angeles")
    // US clocks spring forward on Mar 8, 2026, so that day is 23 hours long.
    let entries = ["2026-03-07T20:00:00Z", "2026-03-08T20:00:00Z", "2026-03-09T20:00:00Z"].map {
        ListeningEntry(start: date($0), real: 60, content: 60)
    }
    #expect(ListeningStats(entries: entries, calendar: losAngeles).streak(asOf: date("2026-03-09T22:00:00Z")) == 3)
}

@Test func `empty history has no streak and empty buckets`() {
    let stats = ListeningStats(entries: [], calendar: utc)
    let now = date("2026-03-05T08:00:00Z")
    #expect(stats.streak(asOf: now) == 0)
    #expect(stats.total == ListeningTotals())
    #expect(stats.daily(count: 7, endingAt: now).count == 7)
    #expect(stats.weekly(count: 4, endingAt: now).count == 4)
}

@Test func `zero length entries are ignored`() {
    let stats = ListeningStats(entries: [ListeningEntry(start: date("2026-03-05T08:00:00Z"), real: 0, content: 0)], calendar: utc)
    #expect(stats.streak(asOf: date("2026-03-05T09:00:00Z")) == 0)
}

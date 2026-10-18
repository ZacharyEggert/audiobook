import Foundation

/// A listening session so far. `id` stays the same across snapshots so the app can update one record.
public struct ListeningSample: Equatable, Sendable {
    public let id: UUID
    public let bookID: UUID
    public let start: Date
    /// Wall-clock seconds spent playing.
    public var real: TimeInterval
    /// Seconds of book played: wall time times the speed it ran at.
    public var content: TimeInterval

    public init(id: UUID, bookID: UUID, start: Date, real: TimeInterval, content: TimeInterval) {
        self.id = id
        self.bookID = bookID
        self.start = start
        self.real = real
        self.content = content
    }
}

/// Measures one stretch of continuous playback, from play to pause (PLAN §5 Stats).
struct ListeningTracker {
    private var sample: ListeningSample?
    private var lastDate = Date.distantPast
    private var rate: Float = 1

    mutating func begin(bookID: UUID, rate: Float, at date: Date) {
        sample = ListeningSample(id: UUID(), bookID: bookID, start: date, real: 0, content: 0)
        lastDate = date
        self.rate = rate
    }

    /// Time up to now counts at the old speed.
    mutating func setRate(_ new: Float, at date: Date) {
        advance(to: date)
        rate = new
    }

    /// The session so far, if one is running.
    mutating func snapshot(at date: Date) -> ListeningSample? {
        advance(to: date)
        return sample
    }

    mutating func end(at date: Date) -> ListeningSample? {
        defer { sample = nil }
        return snapshot(at: date)
    }

    private mutating func advance(to date: Date) {
        guard sample != nil else { return }
        let elapsed = max(date.timeIntervalSince(lastDate), 0) // a clock set back counts as nothing
        sample?.real += elapsed
        sample?.content += elapsed * Double(rate)
        lastDate = date
    }
}

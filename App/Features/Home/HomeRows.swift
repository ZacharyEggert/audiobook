import Foundation
import Library

/// What the Home screen shows, derived from the library and progress (PLAN §6 Screens).
struct HomeRows {
    static let limit = 10

    /// The book to resume: the most recently played one that's in progress.
    var hero: BookRecord?
    var recentlyAdded: [BookRecord] = []
    /// In progress, newest first, without the hero.
    var inProgress: [BookRecord] = []
    var nextInSeries: [BookRecord] = []
    var finishedRecently: [BookRecord] = []

    var isEmpty: Bool {
        hero == nil && recentlyAdded.isEmpty
    }

    init(books: [BookRecord], progress: [UUID: ProgressRecord]) {
        let items = books.map { ($0, BookProgress(book: $0, record: progress[$0.id])) }
        func played(_ status: BookProgress.Status) -> [BookRecord] {
            items.filter { $0.1.status == status }
                .sorted { ($0.1.lastPlayed ?? .distantPast) > ($1.1.lastPlayed ?? .distantPast) }
                .map(\.0)
        }
        let reading = played(.inProgress)
        let finished = played(.finished)
        hero = reading.first
        inProgress = Array(reading.dropFirst().prefix(Self.limit))
        finishedRecently = Array(finished.prefix(Self.limit))
        recentlyAdded = Array(books.sorted { $0.dateAdded > $1.dateAdded }.prefix(Self.limit))

        // The first unstarted book after the last one finished, per series; series read most recently first
        var next: [BookRecord] = []
        var seen: Set<String> = []
        for book in finished {
            guard let series = book.displaySeries, seen.insert(series).inserted else { continue }
            let ordered = books.books(in: LibraryGroup(kind: .series, name: series), collections: [])
            let lastFinished = ordered.lastIndex { progress[$0.id]?.isFinished == true } ?? ordered.startIndex
            let unstarted = ordered[(lastFinished + 1)...].filter { BookProgress(book: $0, record: progress[$0.id]).status == .notStarted }
            if let following = unstarted.first {
                next.append(following)
            }
        }
        nextInSeries = Array(next.prefix(Self.limit))
    }
}

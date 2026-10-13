import Foundation
import Library

enum LibrarySort: String, CaseIterable, Identifiable {
    case recent, title, author, progress, dateAdded

    var id: Self {
        self
    }

    var label: String {
        switch self {
        case .recent: "Recently Played"
        case .title: "Title"
        case .author: "Author"
        case .progress: "Progress"
        case .dateAdded: "Date Added"
        }
    }
}

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all, notStarted, inProgress, finished

    var id: Self {
        self
    }

    var label: String {
        switch self {
        case .all: "All"
        case .notStarted: "Not Started"
        case .inProgress: "In Progress"
        case .finished: "Finished"
        }
    }
}

/// How far the listener is through one book.
struct BookProgress {
    enum Status {
        case notStarted, inProgress, finished
    }

    var position: TimeInterval = 0
    var duration: TimeInterval
    var isFinished = false
    var lastPlayed: Date?

    init(book: BookRecord, record: ProgressRecord?) {
        duration = book.duration
        if let record {
            position = min(max(record.position, 0), book.duration)
            isFinished = record.isFinished
            lastPlayed = record.updatedAt
        }
    }

    var status: Status {
        isFinished ? .finished : position > 0 ? .inProgress : .notStarted
    }

    var fraction: Double {
        isFinished ? 1 : duration > 0 ? position / duration : 0
    }

    var timeLeft: TimeInterval {
        isFinished ? 0 : duration - position
    }

    /// "3h 12m left", "Finished", or the whole length when not started.
    var summary: String {
        switch status {
        case .finished: "Finished"
        case .inProgress: "\(Self.format(timeLeft)) left"
        case .notStarted: Self.format(duration)
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let units: Set<Duration.UnitsFormatStyle.Unit> = seconds >= 60 ? [.hours, .minutes] : [.seconds]
        return Duration.seconds(max(seconds, 0).rounded()).formatted(.units(allowed: units, width: .narrow))
    }
}

extension [BookRecord] {
    /// Filtered, then sorted; title breaks ties so the order is stable.
    func arranged(sort: LibrarySort, filter: LibraryFilter, progress: [UUID: ProgressRecord]) -> [BookRecord] {
        let items = map { ($0, BookProgress(book: $0, record: progress[$0.id])) }
            .filter { _, progress in
                switch filter {
                case .all: true
                case .notStarted: progress.status == .notStarted
                case .inProgress: progress.status == .inProgress
                case .finished: progress.status == .finished
                }
            }
        func byTitle(_ a: BookRecord, _ b: BookRecord) -> Bool {
            a.displayTitle.localizedStandardCompare(b.displayTitle) == .orderedAscending
        }
        return items.sorted { lhs, rhs in
            let (a, aProgress) = lhs, (b, bProgress) = rhs
            switch sort {
            case .title:
                return byTitle(a, b)
            case .author:
                let order = (a.displayAuthors.first ?? "").localizedStandardCompare(b.displayAuthors.first ?? "")
                return order == .orderedSame ? byTitle(a, b) : order == .orderedAscending
            case .dateAdded:
                return a.dateAdded == b.dateAdded ? byTitle(a, b) : a.dateAdded > b.dateAdded
            case .progress:
                return aProgress.fraction == bProgress.fraction ? byTitle(a, b) : aProgress.fraction > bProgress.fraction
            case .recent:
                // Never-played books follow, newest first
                let (aDate, bDate) = (aProgress.lastPlayed ?? .distantPast, bProgress.lastPlayed ?? .distantPast)
                if aDate != bDate {
                    return aDate > bDate
                }
                return a.dateAdded == b.dateAdded ? byTitle(a, b) : a.dateAdded > b.dateAdded
            }
        }
        .map(\.0)
    }
}

import AudiobookCore
import Foundation
import Library
import Playback
import SwiftData

/// Where `PlayerController`'s listening samples land: one `ListeningSessionRecord` per play-to-pause stretch.
enum ListeningLog {
    /// Sessions shorter than this are taps, not listening.
    static let minimumSeconds: TimeInterval = 1

    /// Creates the session's record, or updates it as the session grows.
    static func record(_ sample: ListeningSample, in context: ModelContext) {
        guard sample.real >= minimumSeconds else { return }
        let id = sample.id
        let existing = try? context.fetch(FetchDescriptor<ListeningSessionRecord>(predicate: #Predicate { $0.id == id })).first
        let record = existing ?? ListeningSessionRecord(
            id: id,
            bookID: sample.bookID,
            start: sample.start,
            realSeconds: 0,
            contentSeconds: 0,
        )
        record.realSeconds = sample.real
        record.contentSeconds = sample.content
        if existing == nil {
            context.insert(record)
        }
        try? context.save() // ponytail: a failed save drops up to 5 s of listening; the next sample carries the full total
    }
}

extension [ListeningSessionRecord] {
    var entries: [ListeningEntry] {
        map { ListeningEntry(start: $0.start, real: $0.realSeconds, content: $0.contentSeconds) }
    }
}

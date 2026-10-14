import Foundation
import Library
import SwiftData

/// Where `PlayerController`'s position saves land: one `ProgressRecord` per book (PLAN §4).
enum PlaybackProgress {
    static func save(bookID: UUID, position: TimeInterval, finished: Bool = false, in context: ModelContext) {
        let record = latest(bookID: bookID, in: context) ?? {
            let record = ProgressRecord(bookID: bookID)
            context.insert(record)
            return record
        }()
        record.position = position
        record.updatedAt = .now
        if finished {
            record.isFinished = true
        }
        try? context.save() // ponytail: a failed save loses at most 5 s of position; the next one retries
    }

    /// The most recently played book that is still on this device, and where it was left.
    static func lastBook(in context: ModelContext, files: LibraryFiles) -> (book: BookRecord, position: TimeInterval)? {
        let newestFirst = FetchDescriptor<ProgressRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        for record in (try? context.fetch(newestFirst)) ?? [] {
            let id = record.bookID
            guard let book = try? context.fetch(FetchDescriptor<BookRecord>(predicate: #Predicate { $0.id == id })).first,
                  files.isDownloaded(bookID: id, audioPaths: book.orderedFiles.map(\.relativePath))
            else { continue }
            return (book, record.position)
        }
        return nil
    }

    private static func latest(bookID: UUID, in context: ModelContext) -> ProgressRecord? {
        var descriptor = FetchDescriptor<ProgressRecord>(
            predicate: #Predicate { $0.bookID == bookID },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)],
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

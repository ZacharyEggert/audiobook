import Foundation
import Library
import SwiftData

/// Bookmark storage for the player (PLAN §5 Player): `BookmarkRecord`s keyed by `bookID`, positions in global book seconds.
enum Bookmarks {
    @discardableResult
    static func add(bookID: UUID, position: TimeInterval, note: String? = nil, in context: ModelContext) -> BookmarkRecord {
        let bookmark = BookmarkRecord(bookID: bookID, position: position, note: clean(note))
        context.insert(bookmark)
        try? context.save() // ponytail: a failed save drops one bookmark; the user can add it again
        return bookmark
    }

    static func update(_ bookmark: BookmarkRecord, note: String?, in context: ModelContext) {
        bookmark.note = clean(note)
        try? context.save()
    }

    static func delete(_ bookmark: BookmarkRecord, in context: ModelContext) {
        context.delete(bookmark)
        try? context.save()
    }

    /// The book's bookmarks in book order.
    static func list(bookID: UUID, in context: ModelContext) -> [BookmarkRecord] {
        let descriptor = FetchDescriptor<BookmarkRecord>(
            predicate: #Predicate { $0.bookID == bookID },
            sortBy: [SortDescriptor(\.position), SortDescriptor(\.createdAt)],
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Blank notes are no note.
    private static func clean(_ note: String?) -> String? {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

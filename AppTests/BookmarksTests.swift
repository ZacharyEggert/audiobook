@testable import EarReader
import Foundation
import Library
import SwiftData
import Testing

@MainActor struct BookmarksTests {
    let container = try! LibraryStore.makeContainer(directory: nil) // swiftlint:disable:this force_try
    let bookID = UUID()

    var context: ModelContext {
        container.mainContext
    }

    @Test func `add stores position and trimmed note`() {
        let bookmark = Bookmarks.add(bookID: bookID, position: 123.5, note: "  Litany \n", in: context)
        #expect(bookmark.position == 123.5)
        #expect(bookmark.note == "Litany")
        #expect(Bookmarks.list(bookID: bookID, in: context).count == 1)
    }

    @Test func `blank note is no note`() {
        let bookmark = Bookmarks.add(bookID: bookID, position: 1, note: "  ", in: context)
        #expect(bookmark.note == nil)
        Bookmarks.update(bookmark, note: "Later", in: context)
        #expect(bookmark.note == "Later")
        Bookmarks.update(bookmark, note: "", in: context)
        #expect(bookmark.note == nil)
    }

    @Test func `list is per book and in book order`() {
        Bookmarks.add(bookID: bookID, position: 50, in: context)
        Bookmarks.add(bookID: bookID, position: 10, in: context)
        Bookmarks.add(bookID: UUID(), position: 5, in: context)
        #expect(Bookmarks.list(bookID: bookID, in: context).map(\.position) == [10, 50])
    }

    @Test func `delete removes only that bookmark`() {
        let keep = Bookmarks.add(bookID: bookID, position: 10, in: context)
        let drop = Bookmarks.add(bookID: bookID, position: 20, in: context)
        Bookmarks.delete(drop, in: context)
        #expect(Bookmarks.list(bookID: bookID, in: context).map(\.id) == [keep.id])
    }
}

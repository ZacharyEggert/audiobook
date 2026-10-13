@testable import EarReader
import Foundation
import Library
import SwiftData
import Testing

@MainActor struct LibraryArrangementTests {
    let container = try! LibraryStore.makeContainer(directory: nil) // swiftlint:disable:this force_try
    let books: [BookRecord]
    let progress: [UUID: ProgressRecord]

    init() {
        let day: TimeInterval = 86400
        let unread = BookRecord(title: "Book 10", authors: ["Zed"], duration: 100, dateAdded: .init(timeIntervalSince1970: 3 * day))
        let reading = BookRecord(title: "Book 2", authors: ["Amy"], duration: 100, dateAdded: .init(timeIntervalSince1970: day))
        let done = BookRecord(title: "Another", authors: ["Amy"], duration: 100, dateAdded: .init(timeIntervalSince1970: 2 * day))
        books = [unread, reading, done]
        books.forEach(container.mainContext.insert)
        progress = [
            reading.id: ProgressRecord(bookID: reading.id, position: 40, updatedAt: .init(timeIntervalSince1970: 5 * day)),
            done.id: ProgressRecord(bookID: done.id, position: 100, isFinished: true, updatedAt: .init(timeIntervalSince1970: 4 * day)),
        ]
    }

    func titles(_ sort: LibrarySort, _ filter: LibraryFilter = .all) -> [String] {
        books.arranged(sort: sort, filter: filter, progress: progress).map(\.displayTitle)
    }

    @Test func `sorts each way`() {
        #expect(titles(.title) == ["Another", "Book 2", "Book 10"]) // natural order
        #expect(titles(.author) == ["Another", "Book 2", "Book 10"])
        #expect(titles(.dateAdded) == ["Book 10", "Another", "Book 2"])
        #expect(titles(.progress) == ["Another", "Book 2", "Book 10"])
        #expect(titles(.recent) == ["Book 2", "Another", "Book 10"])
    }

    @Test func `filters by status`() {
        #expect(titles(.title, .notStarted) == ["Book 10"])
        #expect(titles(.title, .inProgress) == ["Book 2"])
        #expect(titles(.title, .finished) == ["Another"])
    }

    @Test func `overrides change the order`() {
        books[2].override = MetadataOverride(title: "Zzz")
        #expect(titles(.title) == ["Book 2", "Book 10", "Zzz"])
    }

    @Test func `summarizes time left`() {
        let reading = BookProgress(
            book: BookRecord(title: "", duration: 3 * 3600 + 30 * 60),
            record: ProgressRecord(bookID: UUID(), position: 18 * 60),
        )
        #expect(reading.summary == "3h 12m left")
        #expect(reading.status == .inProgress)
        #expect(BookProgress(book: BookRecord(title: "", duration: 75), record: nil).summary == "1m")
    }
}

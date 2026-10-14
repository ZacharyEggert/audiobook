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

    @Test func `formats clock times`() {
        #expect(BookProgress.clock(0) == "0:00")
        #expect(BookProgress.clock(65.9) == "1:05")
        #expect(BookProgress.clock(3599) == "59:59")
        #expect(BookProgress.clock(3725) == "1:02:05")
        #expect(BookProgress.clock(-4) == "0:00")
        #expect(BookProgress.clock(.nan) == "0:00")
    }
}

@MainActor struct LibraryGroupTests {
    let container = try! LibraryStore.makeContainer(directory: nil) // swiftlint:disable:this force_try
    let books: [BookRecord]

    init() {
        books = [
            BookRecord(title: "Two", authors: ["Amy"], narrators: ["Ned"], series: "Saga", seriesIndex: 2),
            BookRecord(title: "One", authors: ["Amy", "Bo"], series: "Saga", seriesIndex: 1),
            BookRecord(title: "Extra", authors: ["Bo"], series: "Saga"),
            BookRecord(title: "Loose"),
        ]
        books.forEach(container.mainContext.insert)
    }

    @Test func `groups with counts`() {
        #expect(books.groups(.author).map { "\($0.name) \($0.count)" } == ["Amy 2", "Bo 2", "Unknown Author 1"])
        #expect(books.groups(.narrator).map { "\($0.name) \($0.count)" } == ["Ned 1", "Unknown Narrator 3"])
        #expect(books.groups(.series).map { "\($0.name) \($0.count)" } == ["Saga 3"])
    }

    @Test func `drills into a group`() {
        let saga = LibraryGroup(kind: .series, name: "Saga")
        #expect(books.books(in: saga, collections: []).map(\.title) == ["One", "Two", "Extra"])
        let unknown = LibraryGroup(kind: .author, name: "Unknown Author")
        #expect(books.books(in: unknown, collections: []).map(\.title) == ["Loose"])
    }

    @Test func `keeps a collection's order and skips missing books`() {
        let collection = CollectionRecord(name: "Faves", bookIDs: [books[3].id, UUID(), books[0].id])
        let group = LibraryGroup(kind: .collection(collection.id), name: "Faves")
        #expect(books.books(in: group, collections: [collection]).map(\.title) == ["Loose", "Two"])
    }
}

@testable import EarReader
import Foundation
import Library
import SwiftData
import Testing

@MainActor struct PlaybackProgressTests {
    let container = try! LibraryStore.makeContainer(directory: nil) // swiftlint:disable:this force_try
    let files = LibraryFiles(root: URL.temporaryDirectory.appending(path: UUID().uuidString))

    var context: ModelContext {
        container.mainContext
    }

    /// A book whose one audio file exists only if `downloaded`.
    func book(_ title: String, downloaded: Bool = true) throws -> BookRecord {
        let book = BookRecord(title: title)
        book.files = [FileRecord(index: 0, relativePath: "a.mp3", duration: 60, globalOffset: 0, format: "mp3")]
        context.insert(book)
        if downloaded {
            try FileManager.default.createDirectory(at: files.folder(for: book.id), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: files.folder(for: book.id).appending(path: "a.mp3").path, contents: Data())
        }
        return book
    }

    @Test func `save updates one record per book`() throws {
        let book = try book("A")
        PlaybackProgress.save(bookID: book.id, position: 10, in: context)
        PlaybackProgress.save(bookID: book.id, position: 20, in: context)
        let records = try context.fetch(FetchDescriptor<ProgressRecord>())
        #expect(records.count == 1)
        #expect(records.first?.position == 20)
        #expect(records.first?.isFinished == false)
        PlaybackProgress.save(bookID: book.id, position: 60, finished: true, in: context)
        #expect(records.first?.isFinished == true)
    }

    @Test func `restores the newest downloaded book that still exists`() throws {
        let older = try book("Older")
        let evicted = try book("Evicted", downloaded: false)
        context.insert(ProgressRecord(bookID: older.id, position: 30, updatedAt: .init(timeIntervalSince1970: 1)))
        context.insert(ProgressRecord(bookID: evicted.id, position: 40, updatedAt: .init(timeIntervalSince1970: 2)))
        context.insert(ProgressRecord(bookID: UUID(), position: 50, updatedAt: .init(timeIntervalSince1970: 3))) // deleted book
        let last = try #require(PlaybackProgress.lastBook(in: context, files: files))
        #expect(last.book.id == older.id)
        #expect(last.position == 30)
    }

    @Test func `nothing to restore without progress`() throws {
        _ = try book("Unplayed")
        #expect(PlaybackProgress.lastBook(in: context, files: files) == nil)
    }

    @Test func `mark finished then unfinished at the end restarts`() throws {
        let book = try book("A")
        PlaybackProgress.save(bookID: book.id, position: 60, finished: true, in: context)
        PlaybackProgress.setFinished(false, bookID: book.id, duration: 60, in: context)
        let record = try #require(context.fetch(FetchDescriptor<ProgressRecord>()).first)
        #expect(!record.isFinished)
        #expect(record.position == 0)
    }

    @Test func `unfinishing mid-book keeps position, finishing a new book makes a record`() throws {
        let book = try book("A")
        PlaybackProgress.setFinished(true, bookID: book.id, duration: 60, in: context)
        #expect(try context.fetch(FetchDescriptor<ProgressRecord>()).first?.isFinished == true)
        PlaybackProgress.save(bookID: book.id, position: 20, in: context)
        PlaybackProgress.setFinished(false, bookID: book.id, duration: 60, in: context)
        #expect(try context.fetch(FetchDescriptor<ProgressRecord>()).first?.position == 20)
    }

    @Test func `reset returns to not started`() throws {
        let book = try book("A")
        PlaybackProgress.save(bookID: book.id, position: 60, finished: true, in: context)
        PlaybackProgress.reset(bookID: book.id, in: context)
        let record = try #require(context.fetch(FetchDescriptor<ProgressRecord>()).first)
        #expect(BookProgress(book: book, record: record).status == .notStarted)
        #expect(PlaybackProgress.position(of: book.id, in: context) == 0)
    }

    @Test func `next in series follows index and ends at the last`() {
        func entry(_ title: String, _ index: Double?) -> BookRecord {
            BookRecord(title: title, series: "S", seriesIndex: index)
        }
        let (one, two, three) = (entry("1", 1), entry("2", 2), entry("3", 3))
        let books = [three, one, two, BookRecord(title: "Standalone")]
        #expect(books.nextInSeries(after: one)?.id == two.id)
        #expect(books.nextInSeries(after: two)?.id == three.id)
        #expect(books.nextInSeries(after: three) == nil)
        #expect(books.nextInSeries(after: books[3]) == nil)
    }
}

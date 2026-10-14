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
}

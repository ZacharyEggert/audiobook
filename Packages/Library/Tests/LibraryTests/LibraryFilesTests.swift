import Foundation
@testable import Library
import SwiftData
import Testing

/// A library with `multi-mp3` imported, plus progress, a bookmark and a collection for it.
private struct ImportedBook {
    let root = FileManager.default.temporaryDirectory.appending(path: "library-\(UUID())", directoryHint: .isDirectory)
    let container: ModelContainer
    let context: ModelContext
    let book: BookRecord
    let files: LibraryFiles

    init() async throws {
        container = try LibraryStore.makeContainer(directory: nil)
        let importer = LibraryImporter(modelContainer: container, root: root, availableCapacity: { _ in .max })
        _ = try await importer.importItems([fixture("multi-mp3")])
        context = ModelContext(container)
        book = try #require(try context.fetch(FetchDescriptor<BookRecord>()).first)
        context.insert(ProgressRecord(bookID: book.id, position: 2))
        context.insert(BookmarkRecord(bookID: book.id, position: 1))
        context.insert(CollectionRecord(name: "Faves", bookIDs: [book.id, UUID()]))
        try context.save()
        files = LibraryFiles(root: root)
    }

    var audioPaths: [String] {
        book.orderedFiles.map(\.relativePath)
    }

    func count<Model: PersistentModel>(_: Model.Type) throws -> Int {
        try context.fetchCount(FetchDescriptor<Model>())
    }
}

@Test func `removing a download frees space and keeps the book`() async throws {
    let library = try await ImportedBook()
    defer { try? FileManager.default.removeItem(at: library.root) }
    let before = try #require(await library.files.usage(of: [library.book.id])[library.book.id])
    #expect(before > 0)
    #expect(library.files.isDownloaded(bookID: library.book.id, audioPaths: library.audioPaths))

    try library.files.removeDownload(bookID: library.book.id, audioPaths: library.audioPaths)

    let after = try #require(await library.files.usage(of: [library.book.id])[library.book.id])
    #expect(after < before)
    #expect(!library.files.isDownloaded(bookID: library.book.id, audioPaths: library.audioPaths))
    #expect(FileManager.default.fileExists(atPath: library.files.folder(for: library.book.id).appending(path: "cover.jpg").path))
    #expect(try library.count(BookRecord.self) == 1)
    #expect(try library.count(ProgressRecord.self) == 1)
    #expect(try library.count(BookmarkRecord.self) == 1)
}

@Test func `deleting a book removes it everywhere`() async throws {
    let library = try await ImportedBook()
    defer { try? FileManager.default.removeItem(at: library.root) }
    let id = library.book.id

    try library.context.deleteBook(library.book, files: library.files)

    #expect(!FileManager.default.fileExists(atPath: library.files.folder(for: id).path))
    #expect(await library.files.usage(of: [id])[id] == 0)
    #expect(try library.count(BookRecord.self) == 0)
    #expect(try library.count(FileRecord.self) == 0)
    #expect(try library.count(ProgressRecord.self) == 0)
    #expect(try library.count(BookmarkRecord.self) == 0)
    let collection = try #require(try library.context.fetch(FetchDescriptor<CollectionRecord>()).first)
    #expect(collection.bookIDs.count == 1 && !collection.bookIDs.contains(id))
}

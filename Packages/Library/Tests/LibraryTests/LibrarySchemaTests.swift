import AudiobookCore
import Foundation
@testable import Library
import SwiftData
import Testing

private func sampleBook(in context: ModelContext) -> BookRecord {
    let book = BookRecord(title: "Dune", authors: ["Frank Herbert"], duration: 30)
    context.insert(book)
    book.files = [
        FileRecord(index: 1, relativePath: "02.mp3", duration: 20, globalOffset: 10, format: "mp3"),
        FileRecord(index: 0, relativePath: "01.mp3", duration: 10, globalOffset: 0, format: "mp3"),
    ]
    book.chapters = [
        ChapterRecord(index: 1, title: "Two", start: 10, end: 30),
        ChapterRecord(index: 0, title: "One", start: 0, end: 10),
    ]
    return book
}

@Test func `creates, reads, updates and deletes a book`() throws {
    let container = try LibraryStore.makeContainer(directory: nil)
    let context = ModelContext(container)
    let id = sampleBook(in: context).id
    try context.save()

    let reader = ModelContext(container)
    let fetched = try #require(reader.fetch(FetchDescriptor<BookRecord>(predicate: #Predicate { $0.id == id })).first)
    #expect(fetched.orderedFiles.map(\.relativePath) == ["01.mp3", "02.mp3"])
    #expect(try #require(fetched.book.timeline.locate(15)) == (1, 5))
    #expect(fetched.book.chapters.map(\.title) == ["One", "Two"])

    fetched.title = "Dune (Unabridged)"
    try reader.save()
    #expect(try context.fetch(FetchDescriptor<BookRecord>()).first?.title == "Dune (Unabridged)")

    reader.delete(fetched)
    try reader.save()
    #expect(try reader.fetchCount(FetchDescriptor<BookRecord>()) == 0)
    #expect(try reader.fetchCount(FetchDescriptor<FileRecord>()) == 0) // cascade
    #expect(try reader.fetchCount(FetchDescriptor<ChapterRecord>()) == 0)
}

@Test func `overrides win over file metadata`() throws {
    let context = try ModelContext(LibraryStore.makeContainer(directory: nil))
    let book = sampleBook(in: context)
    book.override = MetadataOverride(title: "Edited", narrators: ["Scott Brick"])
    try context.save()

    #expect(book.book.title == "Edited")
    #expect(book.book.authors == ["Frank Herbert"])
    #expect(book.book.narrators == ["Scott Brick"])
    book.title = "Rescanned" // a re-scan updates the record, not the override
    #expect(book.book.title == "Edited")
}

@Test func `synced records outlive their book`() throws {
    let container = try LibraryStore.makeContainer(directory: nil)
    let context = ModelContext(container)
    let book = sampleBook(in: context)
    context.insert(ProgressRecord(bookID: book.id, position: 12))
    context.insert(BookmarkRecord(bookID: book.id, position: 5, note: "Litany"))
    context.insert(CollectionRecord(name: "Sci-fi", bookIDs: [book.id]))
    try context.save()

    context.delete(book)
    try context.save()

    let reader = ModelContext(container)
    #expect(try reader.fetch(FetchDescriptor<ProgressRecord>()).map(\.position) == [12])
    #expect(try reader.fetch(FetchDescriptor<BookmarkRecord>()).map(\.note) == ["Litany"])
    let collection = try #require(reader.fetch(FetchDescriptor<CollectionRecord>()).first)
    collection.bookIDs.append(UUID())
    try reader.save()
    #expect(try ModelContext(container).fetch(FetchDescriptor<CollectionRecord>()).first?.bookIDs.count == 2)
}

@Test func `persists to disk`() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "store-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    do {
        let context = try ModelContext(LibraryStore.makeContainer(directory: directory))
        let book = sampleBook(in: context)
        context.insert(ProgressRecord(bookID: book.id, position: 3))
        try context.save()
    }
    let context = try ModelContext(LibraryStore.makeContainer(directory: directory))
    #expect(try context.fetchCount(FetchDescriptor<BookRecord>()) == 1)
    #expect(try context.fetchCount(FetchDescriptor<ProgressRecord>()) == 1)
}

/// The rules CloudKit mirroring enforces at container creation, checked here because tests can't enable CloudKit.
@Test func `schema is CloudKit compatible`() {
    for entity in Schema(versionedSchema: LibrarySchemaV2.self).entities {
        #expect(entity.uniquenessConstraints.isEmpty, "\(entity.name) has a unique constraint")
        for relationship in entity.relationships {
            #expect(relationship.isOptional, "\(entity.name).\(relationship.name) isn't optional")
        }
        for attribute in entity.attributes {
            #expect(attribute.isOptional || attribute.defaultValue != nil, "\(entity.name).\(attribute.name) has no default")
            #expect(!attribute.isUnique, "\(entity.name).\(attribute.name) is unique")
        }
    }
}

@Test func `a version 1 store migrates to version 2 keeping its books`() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    do {
        let schema = Schema(versionedSchema: LibrarySchemaV1.self)
        let legacy = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                "Library",
                schema: schema,
                url: directory.appending(path: "Library.store"),
                cloudKitDatabase: .none,
            ),
        )
        let context = ModelContext(legacy)
        _ = sampleBook(in: context)
        try context.save()
    }
    let context = try ModelContext(LibraryStore.makeContainer(directory: directory))
    #expect(try context.fetchCount(FetchDescriptor<BookRecord>()) == 1)
    context.insert(ListeningSessionRecord(bookID: UUID(), start: .now, realSeconds: 5, contentSeconds: 5))
    try context.save()
    #expect(try context.fetchCount(FetchDescriptor<ListeningSessionRecord>()) == 1)
}

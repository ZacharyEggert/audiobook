import AudiobookCore
import Foundation
@testable import Library
import MediaParsing
import SwiftData
import Testing

/// An importer over a temporary library folder and an in-memory store.
private struct Harness {
    let root = FileManager.default.temporaryDirectory.appending(path: "library-\(UUID())", directoryHint: .isDirectory)
    let container: ModelContainer
    let importer: LibraryImporter

    init(capacity: Int64 = .max) throws {
        container = try LibraryStore.makeContainer(directory: nil)
        importer = LibraryImporter(modelContainer: container, root: root, availableCapacity: { _ in capacity })
    }

    func books() throws -> [BookRecord] {
        try ModelContext(container).fetch(FetchDescriptor<BookRecord>(sortBy: [SortDescriptor(\.title)]))
    }

    /// Everything under `root`, staging included, relative to it.
    func contents() -> [String] {
        let all = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []
        let base = root.resolvingSymlinksInPath().pathComponents.count
        return all.map { $0.resolvingSymlinksInPath().pathComponents.dropFirst(base).joined(separator: "/") }.sorted()
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

/// A scratch folder outside the library, for sources the test may change.
private func scratch() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "sources-\(UUID())", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

struct ImportCase: CustomTestStringConvertible, Sendable {
    var items: [String]
    var title: String
    var files: [String]
    var chapters: [String]
    var duration: TimeInterval

    var testDescription: String {
        items.joined(separator: " + ")
    }
}

private let threeChapters = ["Opening", "Middle", "Ending"]

private let cases: [ImportCase] = [
    ImportCase(items: ["chapters.m4b"], title: "Chapters Fixture", files: ["chapters.m4b"], chapters: threeChapters, duration: 6),
    ImportCase(
        items: ["both-chapters.m4b"], title: "Chapters Fixture", files: ["both-chapters.m4b"], chapters: threeChapters, duration: 6,
    ),
    ImportCase(
        items: ["nero-chapters.m4b"], title: "Chapters Fixture", files: ["nero-chapters.m4b"], chapters: threeChapters, duration: 6,
    ),
    ImportCase(items: ["chapters.mp3"], title: "Chapters Fixture", files: ["chapters.mp3"], chapters: threeChapters, duration: 6),
    ImportCase(items: ["chapters.flac"], title: "Chapters Fixture", files: ["chapters.flac"], chapters: threeChapters, duration: 6),
    ImportCase(
        items: ["book.mp3", "book.cue"], title: "Cue Fixture", files: ["book.mp3"],
        chapters: ["Part One", "Part Two", "Part Three"], duration: 6.084,
    ),
    ImportCase(
        items: ["overdrive.mp3"], title: "Überdrive Fixture", files: ["overdrive.mp3"],
        chapters: ["Chapter 1", "Chapter 2", "Chapter 3"], duration: 6,
    ),
    ImportCase(items: ["vbr.mp3"], title: "vbr", files: ["vbr.mp3"], chapters: ["vbr"], duration: 10),
    ImportCase(
        items: ["multi-mp3"], title: "Multi MP3 Fixture", files: ["Part 1.mp3", "Part 2.mp3", "Part 10.mp3"],
        chapters: ["Part One", "Part Two", "Part Ten"], duration: 6,
    ),
    ImportCase(
        items: ["multi-disc"], title: "Multi Disc Fixture", files: ["CD1/01.mp3", "CD1/02.mp3", "CD2/01.mp3", "CD2/02.mp3"],
        chapters: ["Disc 1 Track 1", "Disc 1 Track 2", "Disc 2 Track 1", "Disc 2 Track 2"], duration: 8,
    ),
]

@Test(arguments: cases)
func `imports each fixture as the expected book`(expected: ImportCase) async throws {
    let harness = try Harness()
    defer { harness.remove() }
    let summary = try await harness.importer.importItems(expected.items.map(fixture))

    #expect(summary.failures == [])
    let book = try #require(try harness.books().only)
    #expect(summary.bookIDs == [book.id])
    #expect(book.title == expected.title)
    #expect(book.orderedFiles.map(\.relativePath) == expected.files)
    #expect(book.orderedChapters.map(\.title) == expected.chapters)
    #expect(abs(book.duration - expected.duration) < 0.5)
    #expect(book.orderedChapters.last?.end == book.duration)
    for file in expected.files {
        #expect(FileManager.default.fileExists(atPath: harness.importer.folder(for: book.id).appending(path: file).path))
    }
    #expect(!harness.contents().contains { $0.hasPrefix(".staging/") }) // staging cleaned up
}

@Test func `reads tags into the record`() async throws {
    let harness = try Harness()
    defer { harness.remove() }
    _ = try await harness.importer.importItems([fixture("nero-chapters.m4b"), fixture("chapters.m4b")])

    let books = try harness.books()
    #expect(books.count == 2)
    #expect(books.allSatisfy { $0.authors == ["Test Author"] && $0.year == 2024 })
    #expect(books.compactMap(\.series) == ["Fixture Saga"])
    #expect(books.contains { $0.narrators == ["Test Narrator"] })
}

@Test func `keeps folder images with the book`() async throws {
    let harness = try Harness()
    defer { harness.remove() }
    let id = try #require(try await harness.importer.importItems([fixture("multi-mp3")]).bookIDs.first)
    #expect(FileManager.default.fileExists(atPath: harness.importer.folder(for: id).appending(path: "cover.jpg").path))
}

@Test func `collects failures without stopping`() async throws {
    let harness = try Harness()
    defer { harness.remove() }
    let sources = try scratch()
    defer { try? FileManager.default.removeItem(at: sources) }
    let aax = sources.appending(path: "drm.aax")
    let notes = sources.appending(path: "notes.txt")
    try Data("x".utf8).write(to: aax)
    try Data("x".utf8).write(to: notes)

    let summary = try await harness.importer.importItems([fixture("corrupt.m4b"), fixture("book.zip"), aax, notes, fixture("vbr.mp3")])

    #expect(summary.bookIDs.count == 1)
    #expect(summary.failures.map(\.path).sorted() == ["book.zip", "corrupt.m4b", "drm.aax", "notes.txt"])
    #expect(summary.failures.first { $0.path == "drm.aax" }?.reason == UnsupportedFormat.audible.reason)
    #expect(try harness.books().map(\.title) == ["vbr"])
}

@Test func `refuses an import that doesn't fit`() async throws {
    let harness = try Harness(capacity: 1000)
    defer { harness.remove() }
    await #expect(throws: ImportError.self) { try await harness.importer.importItems([fixture("multi-mp3")]) }
    #expect(try harness.books().isEmpty)
    #expect(harness.contents().allSatisfy { $0 == ".staging" })
}

@Test(arguments: [ImportProgress.Phase.copying, .reading, .saving])
func `cancelling leaves no orphans`(phase: ImportProgress.Phase) async throws {
    let harness = try Harness()
    defer { harness.remove() }
    let importer = harness.importer
    let task = Task {
        try await importer.importItems([fixture("multi-mp3"), fixture("chapters.m4b")]) { progress in
            if progress.phase == phase, progress.completed == 1 {
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(try harness.books().isEmpty)
    #expect(harness.contents() == [".staging"])
}

@Test func `removes sources when asked`() async throws {
    let harness = try Harness()
    defer { harness.remove() }
    let sources = try scratch()
    defer { try? FileManager.default.removeItem(at: sources) }
    let folder = sources.appending(path: "multi-mp3")
    try FileManager.default.copyItem(at: fixture("multi-mp3"), to: folder)

    let summary = try await harness.importer.importItems([folder], removingSources: true)
    #expect(summary.bookIDs.count == 1)
    #expect(!FileManager.default.fileExists(atPath: folder.path))
}

@Test func `streams progress then the summary`() async throws {
    let harness = try Harness()
    defer { harness.remove() }
    var events: [ImportEvent] = []
    for try await event in harness.importer.importEvents([fixture("chapters.m4b")]) {
        events.append(event)
    }
    let phases = events.compactMap {
        if case let .progress(progress) = $0 {
            progress.phase
        } else {
            nil
        }
    }
    #expect(phases == [.copying, .reading, .saving])
    guard case let .finished(summary) = events.last else {
        Issue.record("no summary")
        return
    }
    #expect(summary.bookIDs.count == 1)
}

@Test func `keeps picks with clashing names apart`() async throws {
    let harness = try Harness()
    defer { harness.remove() }
    _ = try await harness.importer.importItems([fixture("vbr.mp3"), fixture("vbr.mp3")])
    // Loose short files are one book, like a folder of them
    #expect(try Set(#require(harness.books().only).files.map(\.relativePath)) == ["vbr.mp3", "vbr 2.mp3"])
}

private extension Array {
    var only: Element? {
        count == 1 ? first : nil
    }
}

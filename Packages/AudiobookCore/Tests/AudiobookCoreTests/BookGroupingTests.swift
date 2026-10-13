@testable import AudiobookCore
import Foundation
import Testing

/// A file tree and the books it should group into, as `"<name>: <path>, <path>"` (plus `" ⚠︎"` when flagged).
struct GroupingCase: CustomTestStringConvertible, Sendable {
    var label: String
    var files: [GroupingFile]
    var books: [String]

    var testDescription: String {
        label
    }
}

private let hours: TimeInterval = 3600

private func mp3(_ path: String, album: String? = "Book", artist: String? = "Author", track: Int? = nil, disc: Int? = nil) -> GroupingFile {
    GroupingFile(path: path, album: album, artist: artist, trackNumber: track, discNumber: disc, duration: 1800)
}

private func m4b(_ path: String, album: String? = nil, track: Int? = nil, chapters: Bool = true) -> GroupingFile {
    m4b(path, album: album, track: track, chapters: chapters, duration: 5 * hours)
}

private func m4b(_ path: String, album: String?, track: Int?, chapters: Bool, duration: TimeInterval) -> GroupingFile {
    GroupingFile(path: path, album: album, trackNumber: track, duration: duration, hasChapters: chapters, isMP4: true)
}

private let cases: [GroupingCase] = [
    GroupingCase(label: "single file", files: [m4b("Dune.m4b")], books: ["Dune: Dune.m4b"]),
    GroupingCase(
        label: "short single file without chapters",
        files: [GroupingFile(path: "clip.mp3", duration: 30)], books: ["clip: clip.mp3"],
    ),
    GroupingCase(
        label: "folder of mp3s in natural order",
        files: [mp3("Book/Part 10.mp3"), mp3("Book/Part 2.mp3"), mp3("Book/Part 1.mp3")],
        books: ["Book: Book/Part 1.mp3, Book/Part 2.mp3, Book/Part 10.mp3"],
    ),
    GroupingCase(
        label: "track numbers beat filenames",
        files: [mp3("Book/a.mp3", track: 2), mp3("Book/b.mp3", track: 1)],
        books: ["Book: Book/b.mp3, Book/a.mp3"],
    ),
    GroupingCase(
        label: "repeated track numbers fall back to filenames",
        files: [mp3("Book/b.mp3", track: 1), mp3("Book/a.mp3", track: 1)],
        books: ["Book: Book/a.mp3, Book/b.mp3"],
    ),
    GroupingCase(
        label: "disc tags then track",
        files: [mp3("Book/x.mp3", track: 1, disc: 2), mp3("Book/y.mp3", track: 2, disc: 1), mp3("Book/z.mp3", track: 1, disc: 1)],
        books: ["Book: Book/z.mp3, Book/y.mp3, Book/x.mp3"],
    ),
    GroupingCase(
        label: "disc subfolders merge in numeric order",
        files: [
            mp3("Book/CD10/01.mp3", track: 1), mp3("Book/CD2/02.mp3", track: 2), mp3("Book/CD2/01.mp3", track: 1),
            mp3("Book/Disc 1/01.mp3", track: 1),
        ],
        books: ["Book: Book/Disc 1/01.mp3, Book/CD2/01.mp3, Book/CD2/02.mp3, Book/CD10/01.mp3"],
    ),
    GroupingCase(
        label: "part subfolders without tags",
        files: [mp3("Book/Part 03/a.mp3", album: nil), mp3("Book/part_1/a.mp3", album: nil)],
        books: ["Book: Book/part_1/a.mp3, Book/Part 03/a.mp3"],
    ),
    GroupingCase(
        label: "a title containing Part stays its own folder",
        files: [mp3("Dune Part 2/01.mp3"), mp3("Dune Part 2/02.mp3")],
        books: ["Dune Part 2: Dune Part 2/01.mp3, Dune Part 2/02.mp3"],
    ),
    GroupingCase(
        label: "folder of m4bs gives one book each",
        files: [m4b("Series/Book 2.m4b"), m4b("Series/Book 1.m4b")],
        books: ["Book 1: Series/Book 1.m4b", "Book 2: Series/Book 2.m4b"],
    ),
    GroupingCase(
        label: "long m4bs without chapters are standalone",
        files: [m4b("Series/A.m4b", chapters: false), m4b("Series/B.m4b", chapters: false)],
        books: ["A: Series/A.m4b", "B: Series/B.m4b"],
    ),
    GroupingCase(
        label: "short m4bs without chapters are one book",
        files: [
            m4b("Book/1.m4b", album: nil, track: nil, chapters: false, duration: 600),
            m4b("Book/2.m4b", album: nil, track: nil, chapters: false, duration: 600),
        ],
        books: ["Book: Book/1.m4b, Book/2.m4b"],
    ),
    GroupingCase(
        label: "m4b parts sharing an album are one book",
        files: [m4b("Book/b.m4b", album: "Saga", track: 2), m4b("Book/a.m4b", album: "Saga", track: 1)],
        books: ["Book: Book/a.m4b, Book/b.m4b"],
    ),
    GroupingCase(
        label: "long mp3 parts stay one book",
        files: [mp3("Book/1.mp3", album: nil), GroupingFile(path: "Book/2.mp3", duration: 2 * hours)],
        books: ["Book: Book/1.mp3, Book/2.mp3"],
    ),
    GroupingCase(
        label: "disagreeing tags are flagged",
        files: [mp3("Mixed/1.mp3", album: "One"), mp3("Mixed/2.mp3", album: "Two")],
        books: ["Mixed: Mixed/1.mp3, Mixed/2.mp3 ⚠︎"],
    ),
    GroupingCase(
        label: "tags differing only in case agree",
        files: [mp3("Book/1.mp3", artist: "Ann Leckie"), mp3("Book/2.mp3", artist: "ann leckie "), mp3("Book/3.mp3", artist: nil)],
        books: ["Book: Book/1.mp3, Book/2.mp3, Book/3.mp3"],
    ),
    GroupingCase(
        label: "nested book folders stay apart",
        files: [mp3("Author/One/1.mp3"), mp3("Author/Two/1.mp3"), m4b("Author/Three.m4b")],
        books: ["Author: Author/Three.m4b", "One: Author/One/1.mp3", "Two: Author/Two/1.mp3"],
    ),
    GroupingCase(
        label: "loose short files are one book",
        files: [mp3("02.mp3"), mp3("01.mp3")],
        books: ["01: 01.mp3, 02.mp3"],
    ),
    GroupingCase(label: "nothing", files: [], books: []),
]

@Test(arguments: cases)
func `groups file trees into books`(testCase: GroupingCase) {
    let books = BookGrouping.group(testCase.files).map { group in
        "\(group.name): \(group.files.map(\.path).joined(separator: ", "))\(group.needsReview ? " ⚠︎" : "")"
    }
    #expect(books == testCase.books)
}

@Test func `reads disc folder numbers`() {
    #expect(BookGrouping.discNumber("CD1") == 1)
    #expect(BookGrouping.discNumber("disk 12") == 12)
    #expect(BookGrouping.discNumber("Part-03 (bonus)") == 3)
    #expect(BookGrouping.discNumber("Dune Part 2") == nil)
    #expect(BookGrouping.discNumber("CD1A") == nil)
    #expect(BookGrouping.discNumber("Discworld 3") == nil)
}

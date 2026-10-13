@testable import AudiobookCore
import Foundation
import Testing

private func summary(_ chapters: [Chapter]) -> [String] {
    chapters.map { "\($0.index) \($0.title) \($0.start)-\($0.end)" }
}

@Test func `one chapter per file without chapters`() {
    let chapters = Chapter.normalized([FileChapters(duration: 10, title: "One"), FileChapters(duration: 5, title: "Two")])
    #expect(summary(chapters) == ["0 One 0.0-10.0", "1 Two 10.0-15.0"])
}

@Test func `offsets each file's own chapters`() {
    let chapters = Chapter.normalized([
        FileChapters(duration: 10, title: "One", chapters: [(0, "A"), (4, "B")]),
        FileChapters(duration: 6, title: "Two"),
        FileChapters(duration: 8, title: "Three", chapters: [(3, "D"), (0, "C")]), // unsorted
    ])
    #expect(summary(chapters) == ["0 A 0.0-4.0", "1 B 4.0-10.0", "2 Two 10.0-16.0", "3 C 16.0-19.0", "4 D 19.0-24.0"])
}

@Test func `drops zero-length, repeated and out-of-range starts`() {
    let chapters = Chapter.normalized([
        FileChapters(duration: 10, title: "One", chapters: [(0, "Dup"), (0, "A"), (5, "B"), (5, "B"), (10, "Past end"), (.nan, "NaN")]),
        FileChapters(duration: 0, title: "Empty"),
        FileChapters(duration: 4, title: "Two"),
    ])
    #expect(summary(chapters) == ["0 A 0.0-5.0", "1 B 5.0-10.0", "2 Two 10.0-14.0"])
}

@Test func `first chapter starts with its file`() {
    let chapters = Chapter.normalized([FileChapters(duration: 10, title: "One", chapters: [(1.5, "Late"), (6, "Next")])])
    #expect(summary(chapters) == ["0 Late 0.0-6.0", "1 Next 6.0-10.0"])
}

@Test func `names blank chapters`() {
    let chapters = Chapter.normalized([FileChapters(duration: 10, title: "", chapters: [(0, " "), (5, "B")])])
    #expect(chapters.map(\.title) == ["Chapter 1", "B"])
}

@Test func `empty input gives no chapters`() {
    #expect(Chapter.normalized([]).isEmpty)
    #expect(Chapter.normalized([FileChapters(duration: 0, title: "Empty")]).isEmpty)
}

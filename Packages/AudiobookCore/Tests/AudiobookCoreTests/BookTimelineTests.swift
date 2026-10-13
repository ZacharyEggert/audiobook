@testable import AudiobookCore
import Foundation
import Testing

private func book(_ durations: [TimeInterval]) -> Book {
    let files = durations.enumerated().map { AudioFile(relativePath: "\($0.offset).mp3", duration: $0.element, format: "mp3") }
    return Book(
        title: "Fixture", files: files,
        chapters: Chapter.normalized(durations.enumerated().map { FileChapters(duration: $0.element, title: "File \($0.offset)") }),
    )
}

/// Seeded so failures reproduce.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}

@Test func `lays out file offsets`() {
    let book = book([10, 0, 5.5, 20])
    #expect(book.files.map(\.globalOffset) == [0, 10, 10, 15.5])
    #expect(book.duration == 35.5)
}

@Test func `round-trips random times through locate and global`() throws {
    var rng = SplitMix64(state: 42)
    for _ in 0 ..< 200 {
        let durations = (0 ..< Int.random(in: 1 ... 8, using: &rng)).map { _ in
            Bool.random(using: &rng) ? 0 : TimeInterval.random(in: 0.1 ... 5000, using: &rng)
        }
        let timeline = book(durations).timeline
        let times = (0 ..< 20).map { _ in TimeInterval.random(in: 0 ... timeline.duration, using: &rng) }
            + [0, timeline.duration] + timeline.files.map(\.globalOffset)
        for time in times {
            let (index, local) = try #require(timeline.locate(time))
            #expect(local >= 0 && local <= timeline.files[index].duration)
            #expect(abs(timeline.global(fileIndex: index, local: local) - time) < 1e-9)
        }
    }
}

@Test func `boundaries belong to the file that starts there`() throws {
    let timeline = book([10, 0, 5]).timeline
    #expect(try #require(timeline.locate(0)) == (0, 0))
    #expect(try #require(timeline.locate(9.999)).fileIndex == 0)
    #expect(try #require(timeline.locate(10)) == (2, 0)) // skips the zero-length file
    #expect(try #require(timeline.locate(15)) == (2, 5)) // the end stays in the last file
}

@Test func `clamps out-of-range input`() throws {
    let timeline = book([10, 5]).timeline
    #expect(try #require(timeline.locate(-3)) == (0, 0))
    #expect(try #require(timeline.locate(99)) == (1, 5))
    #expect(try #require(timeline.locate(.nan)) == (0, 0))
    #expect(timeline.global(fileIndex: 0, local: 50) == 10)
    #expect(timeline.global(fileIndex: 1, local: -1) == 10)
    #expect(timeline.global(fileIndex: -1, local: 3) == 0)
    #expect(timeline.global(fileIndex: 2, local: 3) == 15)
}

@Test func `empty and one-file books`() throws {
    let empty = book([]).timeline
    #expect(empty.duration == 0)
    #expect(empty.locate(5) == nil)
    #expect(empty.global(fileIndex: 0, local: 1) == 0)
    #expect(empty.chapter(at: 0) == nil)

    let single = book([60]).timeline
    #expect(try #require(single.locate(30)) == (0, 30))
    #expect(single.chapter(at: 30) == Chapter(index: 0, title: "File 0", start: 0, end: 60))
}

@Test func `finds the chapter at a time`() {
    let timeline = BookTimeline(files: [], chapters: [
        Chapter(index: 0, title: "A", start: 2, end: 5),
        Chapter(index: 1, title: "B", start: 5, end: 9),
    ])
    #expect(timeline.chapter(at: 0)?.title == "A")
    #expect(timeline.chapter(at: 4.99)?.title == "A")
    #expect(timeline.chapter(at: 5)?.title == "B")
    #expect(timeline.chapter(at: 100)?.title == "B")
}

import AudiobookCore
import Foundation
@testable import Playback
import Testing

@MainActor struct ScrubberTests {
    /// Two 100 s files; the middle chapter spans the file boundary.
    let book = Book(
        title: "Split",
        files: [
            AudioFile(relativePath: "1.mp3", duration: 100, format: "mp3"),
            AudioFile(relativePath: "2.mp3", duration: 100, format: "mp3"),
        ],
        chapters: [
            Chapter(index: 0, title: "One", start: 0, end: 60),
            Chapter(index: 1, title: "Two", start: 60, end: 140),
            Chapter(index: 2, title: "Three", start: 140, end: 200),
        ],
    )

    func loaded(at position: TimeInterval) async -> PlayerController {
        let player = PlayerController(engine: FakeEngine())
        await player.load(book, folder: URL(filePath: "/tmp"), at: position)
        return player
    }

    @Test func `chapter span covers a chapter that crosses a file boundary`() async {
        let player = await loaded(at: 110)
        let span = player.scrubberSpan(.chapter)
        #expect(span == ScrubberSpan(start: 60, end: 140))
        #expect(span.elapsed(at: 110) == 50)
        #expect(span.remaining(at: 110) == 30)
    }

    @Test func `book span covers every file`() async {
        let player = await loaded(at: 110)
        let span = player.scrubberSpan(.book)
        #expect(span == ScrubberSpan(start: 0, end: 200))
        #expect(span.elapsed(at: 110) == 110)
        #expect(span.remaining(at: 110) == 90)
    }

    @Test func `time left is divided by speed`() async {
        let player = await loaded(at: 110)
        #expect(player.scrubberSpan(.book).timeLeft(at: 110, rate: 1.5) == 60)
        #expect(player.scrubberSpan(.chapter).timeLeft(at: 110, rate: 2) == 15)
    }

    @Test func `position outside the span clamps`() {
        let span = ScrubberSpan(start: 60, end: 140)
        #expect(span.elapsed(at: 10) == 0)
        #expect(span.remaining(at: 500) == 0)
    }

    @Test func `scrub preview names the chapter at the target`() async {
        let player = await loaded(at: 10)
        #expect(player.chapterTitle(at: 150) == "Three")
        #expect(player.chapterTitle(at: 99.9) == "Two")
        #expect(player.chapterTitle(at: 100) == "Two")
    }

    @Test func `mode toggles`() {
        #expect(ScrubberMode.chapter.toggled == .book)
        #expect(ScrubberMode.book.toggled == .chapter)
    }
}

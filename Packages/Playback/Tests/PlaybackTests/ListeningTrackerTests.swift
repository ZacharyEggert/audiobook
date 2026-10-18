import AudiobookCore
import Foundation
@testable import Playback
import Testing

@MainActor final class ListeningTrackerTests {
    let engine = FakeEngine()
    let book = Book(
        title: "One Part",
        files: [AudioFile(relativePath: "1.mp3", duration: 3600, format: "mp3")],
        chapters: [Chapter(index: 0, title: "One", start: 0, end: 3600)],
    )
    let folder = URL(filePath: "/tmp")
    var samples: [ListeningSample] = []

    @Test func `tracker counts book time at the speed it ran at`() {
        let start = Date(timeIntervalSince1970: 1000)
        var tracker = ListeningTracker()
        tracker.begin(bookID: book.id, rate: 1, at: start)
        tracker.setRate(2, at: start + 60)
        let sample = tracker.end(at: start + 90)
        #expect(sample?.start == start)
        #expect(sample?.real == 90)
        #expect(sample?.content == 120) // 60 s at 1x, 30 s at 2x
        #expect(tracker.end(at: start + 100) == nil)
    }

    @Test func `a clock set back counts as nothing`() {
        let start = Date(timeIntervalSince1970: 1000)
        var tracker = ListeningTracker()
        tracker.begin(bookID: book.id, rate: 1, at: start)
        #expect(tracker.snapshot(at: start - 50)?.real == 0)
    }

    @Test func `a play to pause is one session`() async {
        var clock = Date(timeIntervalSince1970: 5000)
        let player = PlayerController(engine: engine, now: { clock })
        player.onListeningSample = { [unowned self] in samples.append($0) }
        await player.load(book, folder: folder)
        player.rate = 1.5
        player.play()
        clock += 40
        player.pause()
        clock += 500 // paused time doesn't count
        let sample = samples.last
        #expect(sample?.bookID == book.id)
        #expect(sample?.start == Date(timeIntervalSince1970: 5000))
        #expect(sample?.real == 40)
        #expect(sample?.content == 60)
    }

    @Test func `saves report the session so far under one id`() async {
        var clock = Date(timeIntervalSince1970: 0)
        let player = PlayerController(engine: engine, now: { clock })
        player.onListeningSample = { [unowned self] in samples.append($0) }
        await player.load(book, folder: folder)
        player.play()
        clock += 10
        player.saveNow()
        clock += 5
        player.pause()
        #expect(samples.map(\.real) == [10, 15]) // the save, then the pause ends the session
        #expect(Set(samples.map(\.id)).count == 1)
    }

    @Test func `pausing and playing again starts a new session`() async {
        var clock = Date(timeIntervalSince1970: 0)
        let player = PlayerController(engine: engine, now: { clock })
        player.onListeningSample = { [unowned self] in samples.append($0) }
        await player.load(book, folder: folder)
        player.play()
        clock += 10
        player.pause()
        clock += 100
        player.play()
        await player.resumeTask?.value // smart rewind delays the engine
        clock += 20
        player.pause()
        #expect(Set(samples.map(\.id)).count == 2)
        #expect(samples.last?.real == 20)
    }

    @Test func `nothing is reported before playing`() async {
        let player = PlayerController(engine: engine)
        player.onListeningSample = { [unowned self] in samples.append($0) }
        await player.load(book, folder: folder)
        player.saveNow()
        #expect(samples.isEmpty)
    }
}

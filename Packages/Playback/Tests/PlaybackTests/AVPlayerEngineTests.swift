import AudiobookCore
import AVFoundation
@testable import Playback
import Testing

/// Integration tests against real fixtures. They play audio briefly, at high rate, so they stay fast.
@MainActor struct AVPlayerEngineTests {
    let engine = AVPlayerEngine()

    @Test func `seeks across a file boundary`() async throws {
        let folder = fixture("multi-mp3")
        let book = try await book(in: folder, ["Part 1.mp3", "Part 2.mp3", "Part 10.mp3"])
        try await engine.load(book, folder: folder, at: 0)
        #expect(engine.items.count == 3)

        await engine.seek(to: 3)
        #expect(abs(engine.currentTime - 3) < 0.01)
        #expect(engine.items.count == 2) // rebuilt from Part 2

        await engine.seek(to: 3.5) // same file
        #expect(abs(engine.currentTime - 3.5) < 0.01)

        await engine.seek(to: 1.8)
        engine.rate = 2
        engine.play()
        #expect(await until { engine.currentTime > 2.3 }) // played into Part 2
        #expect(engine.player.currentItem === engine.items[1])
        engine.pause()
    }

    @Test func `jumps to chapter 3`() async throws {
        let folder = fixture("")
        let chapters = [
            Chapter(index: 0, title: "Opening", start: 0, end: 2),
            Chapter(index: 1, title: "Middle", start: 2, end: 4.5),
            Chapter(index: 2, title: "Ending", start: 4.5, end: 6),
        ]
        let book = try await book(in: folder, ["chapters.m4b"], chapters: chapters)
        try await engine.load(book, folder: folder, at: 0)
        await engine.seek(to: book.chapters[2].start)
        #expect(abs(engine.currentTime - 4.5) < 0.01)
        #expect(book.timeline.chapter(at: engine.currentTime)?.title == "Ending")
    }

    @Test func `rate applies while playing`() async throws {
        let folder = fixture("")
        try await engine.load(book(in: folder, ["chapters.m4b"]), folder: folder, at: 0)
        #expect(engine.items.allSatisfy { $0.audioTimePitchAlgorithm == .timeDomain })
        engine.rate = 1.5
        #expect(engine.player.rate == 0) // paused stays paused
        engine.play()
        #expect(engine.player.rate == 1.5)
        engine.rate = 2
        #expect(engine.player.rate == 2)
        engine.pause()
        #expect(engine.player.rate == 0)
    }

    @Test func `emits ended at the end of the book`() async throws {
        let folder = fixture("multi-mp3")
        let book = try await book(in: folder, ["Part 1.mp3", "Part 2.mp3", "Part 10.mp3"])
        let events = Recorder()
        engine.onEvent = { events.list.append($0) }
        try await engine.load(book, folder: folder, at: book.duration - 0.3)
        engine.rate = 2
        engine.play()
        #expect(await until { engine.state == .ended })
        #expect(events.list.suffix(2) == [.time(book.duration), .state(.ended)])
        #expect(engine.currentTime == book.duration)

        engine.play() // restarts from the top
        #expect(await until { engine.items.count == 3 && engine.player.rate == 2 })
        #expect(engine.currentTime < 1)
        engine.pause()
    }

    @Test func `load throws for a corrupt file`() async throws {
        let folder = fixture("")
        let book = Book(title: "Corrupt", files: [AudioFile(relativePath: "corrupt.m4b", duration: 1, format: "mp4")], chapters: [])
        await #expect(throws: (any Error).self) { try await engine.load(book, folder: folder, at: 0) }
    }
}

@MainActor private final class Recorder {
    var list: [PlaybackEvent] = []
}

/// A book of `paths` in `folder`, with durations read the way the importer reads them.
private func book(in folder: URL, _ paths: [String], chapters: [Chapter] = []) async throws -> Book {
    var files: [AudioFile] = []
    for path in paths {
        let asset = AVURLAsset(url: folder.appending(path: path), options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let duration = try await asset.load(.duration).seconds
        files.append(AudioFile(relativePath: path, duration: duration, format: (path as NSString).pathExtension))
    }
    return Book(title: folder.lastPathComponent, files: files, chapters: chapters)
}

/// Polls `condition` until it holds or `timeout` passes.
@MainActor private func until(timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return true
}

/// A file in the repo's `Tests/Fixtures` (built by `scripts/make-fixtures.sh`).
private func fixture(_ name: String) -> URL {
    URL(filePath: #filePath)
        .deletingLastPathComponent() // PlaybackTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // Playback
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent()
        .appending(path: "Tests/Fixtures/\(name)")
}

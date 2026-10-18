import AudiobookCore
import Foundation
@testable import Playback
import Testing

@MainActor final class SmartRewindTests {
    let engine = FakeEngine()
    let book = Book(
        title: "One Part",
        files: [AudioFile(relativePath: "1.mp3", duration: 120, format: "mp3")],
        chapters: [Chapter(index: 0, title: "One", start: 0, end: 120)],
    )
    let folder = URL(filePath: "/tmp")

    @Test(arguments: [(0.0, 0.0), (59, 0), (60, 5), (599, 5), (600, 15), (3599, 15), (3600, 30), (86400, 30)])
    func `smart rewind table`(pause: TimeInterval, expected: TimeInterval) {
        #expect(SmartRewind.seconds(afterPause: pause) == expected)
    }

    @Test func `resume rewinds by the pause length`() async {
        var clock = Date(timeIntervalSince1970: 0)
        let player = PlayerController(engine: engine, now: { clock })
        await player.load(book, folder: folder, at: 50)
        player.play()
        player.pause()
        clock += 120
        player.play()
        await player.resumeTask?.value
        #expect(player.position == 45)
        #expect(player.isPlaying)
    }

    @Test func `resume after a short pause or with the setting off does not rewind`() async {
        var clock = Date(timeIntervalSince1970: 0)
        let player = PlayerController(engine: engine, now: { clock })
        await player.load(book, folder: folder, at: 50)
        player.play()
        player.pause()
        clock += 30
        player.play()
        #expect(player.position == 50)
        player.pause()
        player.smartRewindEnabled = false
        clock += 7200
        player.play()
        #expect(player.position == 50)
        #expect(player.isPlaying)
    }

    @Test func `first play after a load does not rewind`() async {
        var clock = Date(timeIntervalSince1970: 0)
        let player = PlayerController(engine: engine, now: { clock })
        await player.load(book, folder: folder, at: 50)
        clock += 7200
        player.play()
        #expect(player.position == 50)
    }

    @Test func `pausing again before the rewind finishes stays paused`() async {
        var clock = Date(timeIntervalSince1970: 0)
        let player = PlayerController(engine: engine, now: { clock })
        await player.load(book, folder: folder, at: 50)
        player.play()
        player.pause()
        clock += 120
        player.play()
        player.pause()
        await player.resumeTask?.value
        #expect(!player.isPlaying)
    }
}

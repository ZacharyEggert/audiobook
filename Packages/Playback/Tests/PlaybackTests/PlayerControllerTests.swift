import AudiobookCore
import Foundation
import MediaPlayer
@testable import Playback
import Testing

@MainActor final class PlayerControllerTests {
    let engine = FakeEngine()
    let book = Book(
        title: "Two Parts",
        authors: ["Ann", "Bo"],
        files: [
            AudioFile(relativePath: "1.mp3", duration: 60, format: "mp3"),
            AudioFile(relativePath: "2.mp3", duration: 60, format: "mp3"),
        ],
        chapters: [Chapter(index: 0, title: "One", start: 0, end: 60), Chapter(index: 1, title: "Two", start: 60, end: 120)],
    )
    let folder = URL(filePath: "/tmp")
    lazy var player = PlayerController(engine: engine)
    var saves: [TimeInterval] = []
    var finished: [UUID] = []

    func loaded(at position: TimeInterval = 0) async -> PlayerController {
        let bookID = book.id
        player.onPositionSave = { [unowned self] in
            #expect($0 == bookID)
            saves.append($1)
        }
        player.onBookFinished = { [unowned self] in finished.append($0) }
        await player.load(book, folder: folder, at: position)
        return player
    }

    @Test func `fake engine drives position and chapter`() async {
        let player = await loaded(at: 50)
        #expect(player.chapter?.title == "One")
        player.play()
        engine.advance(by: 15)
        #expect(player.position == 65)
        #expect(player.chapter?.title == "Two")
        #expect(player.chapterElapsed == 5)
    }

    @Test func `load pauses at position at the default rate`() async {
        player.defaultRate = 1.5
        let player = await loaded(at: 30)
        #expect(player.book == book)
        #expect(player.folder == folder)
        #expect(player.state == .paused)
        #expect(player.position == 30)
        #expect(engine.rate == 1.5)
        #expect(saves.isEmpty)
    }

    @Test func `load failure keeps the old book and reports`() async {
        let player = await loaded()
        engine.loadError = CocoaError(.fileNoSuchFile)
        await player.load(Book(title: "Other", files: [], chapters: []), folder: folder)
        #expect(player.book == book)
        #expect(player.lastError != nil)
    }

    @Test func `play pause and toggle`() async {
        let player = await loaded()
        player.play()
        #expect(player.isPlaying)
        player.toggle()
        #expect(player.state == .paused)
        player.toggle()
        #expect(player.isPlaying)
    }

    @Test func `play without a book does nothing`() {
        player.play()
        #expect(player.state == .idle)
    }

    @Test func `seek clamps to the book`() async {
        let player = await loaded()
        await player.seek(to: 200)
        #expect(player.position == 120)
        await player.skip(by: -500)
        #expect(player.position == 0)
        await player.skipForward()
        #expect(player.position == 30)
        await player.skipBack()
        #expect(player.position == 15)
    }

    @Test func `next and previous chapter`() async {
        let player = await loaded(at: 10)
        await player.nextChapter()
        #expect(player.position == 60)
        await player.nextChapter() // last chapter: stays
        #expect(player.position == 60)
        await player.seek(to: 70)
        await player.previousChapter() // > 3 s in: chapter start
        #expect(player.position == 60)
        await player.previousChapter() // at start: chapter before
        #expect(player.position == 0)
        #expect(player.chapter?.title == "One")
    }

    @Test func `end of book saves, finishes and replays from the start`() async {
        let player = await loaded(at: 110)
        player.play()
        engine.advance(by: 20)
        #expect(player.state == .ended)
        #expect(player.position == 120)
        #expect(saves.last == 120)
        #expect(finished == [book.id])
        player.play()
        #expect(player.isPlaying)
        #expect(engine.currentTime == 0)
    }

    @Test func `engine failure is reported`() async {
        let player = await loaded()
        player.play()
        engine.fail("gone")
        #expect(player.lastError == "gone")
        #expect(player.state == .paused)
    }

    @Test func `rate reaches the engine and speeds the clock`() async {
        let player = await loaded()
        player.rate = 2
        #expect(engine.rate == 2)
        player.play()
        engine.advance(by: 3)
        #expect(player.position == 6)
    }

    @Test func `saves every 5 s of playback and on pause`() async {
        let player = await loaded()
        player.play()
        for _ in 0 ..< 12 {
            engine.advance(by: 1)
        }
        #expect(saves == [5, 10])
        player.pause()
        #expect(saves == [5, 10, 12])
        player.saveNow()
        #expect(saves.last == 12)
    }

    @Test func `timing changes are announced, ticks are not`() async {
        var count = 0
        player.onTimingChange = { count += 1 }
        let player = await loaded(at: 50)
        count = 0
        player.play() // state
        engine.advance(by: 1) // tick
        #expect(count == 1)
        engine.advance(by: 10) // chapter
        #expect(count == 2)
        await player.seek(to: 0) // chapter + seek
        player.rate = 1.25
        #expect(count == 5)
    }

    // MARK: Audio session

    @Test func `interruption pauses, saves and resumes when told to`() async {
        let player = await loaded()
        player.play()
        engine.advance(by: 2)
        await player.handle(.interruptionBegan)
        #expect(player.state == .paused)
        #expect(saves == [2])
        await player.handle(.interruptionEnded(shouldResume: true))
        #expect(player.isPlaying)
    }

    @Test func `interruption without shouldResume stays paused`() async {
        let player = await loaded()
        player.play()
        await player.handle(.interruptionBegan)
        await player.handle(.interruptionEnded(shouldResume: false))
        #expect(player.state == .paused)
    }

    @Test func `interruption while paused doesn't start playback`() async {
        let player = await loaded()
        await player.handle(.interruptionBegan)
        await player.handle(.interruptionEnded(shouldResume: true))
        #expect(player.state == .paused)
    }

    @Test func `resumes even if the engine paused before the interruption arrived`() async {
        let player = await loaded()
        player.play()
        engine.pause() // the system stopped the engine first
        await player.handle(.interruptionBegan)
        await player.handle(.interruptionEnded(shouldResume: true))
        #expect(player.isPlaying)
    }

    @Test func `headphones unplugged pauses`() async {
        let player = await loaded()
        player.play()
        await player.handle(.oldDeviceUnavailable)
        #expect(player.state == .paused)
    }

    @Test func `media services reset rebuilds the engine at the same position`() async {
        var engines: [FakeEngine] = []
        let player = PlayerController {
            let engine = FakeEngine()
            engines.append(engine)
            return engine
        }
        player.defaultRate = 1.5
        await player.load(book, folder: folder, at: 0)
        player.play()
        engines[0].advance(by: 20)
        await player.handle(.mediaServicesReset)
        #expect(engines.count == 2)
        #expect(player.engine === engines[1])
        #expect(engines[1].book == book)
        #expect(engines[1].rate == 1.5)
        #expect(player.position == 30)
        #expect(player.state == .paused)
        player.play()
        engines[1].advance(by: 1)
        #expect(player.position == 31.5)
    }

    // MARK: Now Playing

    @Test func `now playing shows chapter time or book time`() async {
        let player = await loaded(at: 70)
        player.rate = 1.5
        var info = NowPlaying.info(for: player, usesChapterTime: true)
        #expect(info[MPMediaItemPropertyTitle] as? String == "Two")
        #expect(info[MPMediaItemPropertyAlbumTitle] as? String == "Two Parts")
        #expect(info[MPMediaItemPropertyArtist] as? String == "Ann, Bo")
        #expect(info[MPMediaItemPropertyPlaybackDuration] as? Double == 60)
        #expect(info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double == 10)
        #expect(info[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 0)
        #expect(info[MPNowPlayingInfoPropertyChapterNumber] as? Int == 1)
        player.play()
        info = NowPlaying.info(for: player, usesChapterTime: false)
        #expect(info[MPMediaItemPropertyPlaybackDuration] as? Double == 120)
        #expect(info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double == 70)
        #expect(info[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1.5)
    }

    @Test func `lock screen scrub maps chapter time to book time`() async {
        let player = await loaded(at: 70)
        #expect(NowPlaying.globalTime(remote: 5, player: player, usesChapterTime: true) == 65)
        #expect(NowPlaying.globalTime(remote: 500, player: player, usesChapterTime: true) == 120)
        #expect(NowPlaying.globalTime(remote: 5, player: player, usesChapterTime: false) == 5)
    }
}

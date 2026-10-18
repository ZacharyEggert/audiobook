import AudiobookCore
import Foundation
@testable import Playback
import Testing

@MainActor final class SleepTimerTests {
    var clock = Date(timeIntervalSince1970: 0)
    var volumes: [Float] = []
    var stops = 0

    /// A timer on the test's clock.
    private func make() -> SleepTimer {
        let timer = SleepTimer(now: { [unowned self] in clock })
        timer.onVolume = { [unowned self] in volumes.append($0) }
        timer.onStop = { [unowned self] in stops += 1 }
        return timer
    }

    private func run(_ timer: SleepTimer, seconds: TimeInterval, position: TimeInterval = 0, rate: Float = 1) {
        clock += seconds
        timer.tick(position: position, rate: rate)
    }

    @Test func `starts off`() {
        #expect(make().state == .off)
    }

    @Test func `a duration runs, fades over the last 10 s and stops`() {
        let timer = make()
        timer.start(.duration(60))
        #expect(timer.state == .running(.duration(60)))
        run(timer, seconds: 30)
        #expect(timer.remaining == 30)
        #expect(timer.state == .running(.duration(60)))
        run(timer, seconds: 25)
        #expect(timer.state == .fading(.duration(60)))
        #expect(volumes == [0.5])
        run(timer, seconds: 2.5)
        #expect(volumes.last == 0.25)
        run(timer, seconds: 3)
        #expect(timer.state == .stopped)
        #expect(timer.remaining == nil)
        #expect(stops == 1)
        #expect(volumes.last == 1)
    }

    @Test func `a pause freezes the countdown`() {
        let timer = make()
        timer.start(.duration(60))
        run(timer, seconds: 20)
        timer.playbackPaused()
        clock += 3600
        timer.playbackStarted()
        run(timer, seconds: 10)
        #expect(timer.remaining == 30)
        #expect(stops == 0)
    }

    @Test func `end of chapter counts down in wall time at the current rate`() {
        let timer = make()
        timer.start(.endOfChapter(end: 100), position: 40, rate: 2)
        #expect(timer.remaining == 30)
        run(timer, seconds: 10, position: 60, rate: 2)
        #expect(timer.remaining == 20)
        run(timer, seconds: 12, position: 84, rate: 2)
        #expect(timer.state == .fading(.endOfChapter(end: 100)))
        run(timer, seconds: 8, position: 100, rate: 2)
        #expect(timer.state == .stopped)
        #expect(stops == 1)
    }

    @Test func `end of chapter still stops when the tick lands past the end`() {
        let timer = make()
        timer.start(.endOfChapter(end: 100), position: 98)
        run(timer, seconds: 1, position: 101)
        #expect(timer.state == .stopped)
    }

    @Test func `starting inside the fade window fades at once`() {
        let timer = make()
        timer.start(.duration(5))
        #expect(timer.state == .fading(.duration(5)))
        #expect(volumes == [0.5])
    }

    @Test func `extend adds the last duration while running`() {
        let timer = make()
        timer.start(.duration(600))
        run(timer, seconds: 100)
        timer.extend()
        #expect(timer.remaining == 1100)
        #expect(timer.state == .running(.duration(600)))
    }

    @Test func `extend during the fade restores volume and keeps playing`() {
        let timer = make()
        timer.start(.duration(60))
        run(timer, seconds: 55)
        #expect(timer.state == .fading(.duration(60)))
        timer.extend()
        #expect(timer.state == .running(.duration(60)))
        #expect(timer.remaining == 65)
        #expect(volumes.last == 1)
    }

    @Test func `extend turns end of chapter into a duration`() {
        let timer = make()
        timer.start(.duration(300))
        timer.start(.endOfChapter(end: 500), position: 0)
        timer.extend(position: 0)
        #expect(timer.state == .running(.duration(300)))
        #expect(timer.remaining == 300)
    }

    @Test func `extend with no duration used adds 15 minutes`() {
        let timer = make()
        timer.start(.endOfChapter(end: 500), position: 0)
        timer.extend(position: 0)
        #expect(timer.remaining == 900)
    }

    @Test func `extend does nothing when off or stopped`() {
        let timer = make()
        timer.extend()
        #expect(timer.state == .off)
        timer.start(.duration(5))
        run(timer, seconds: 6)
        #expect(timer.state == .stopped)
        timer.extend()
        #expect(timer.state == .stopped)
    }

    @Test func `cancel returns to off and restores volume`() {
        let timer = make()
        timer.start(.duration(60))
        run(timer, seconds: 55)
        timer.cancel()
        #expect(timer.state == .off)
        #expect(timer.remaining == nil)
        #expect(volumes.last == 1)
        run(timer, seconds: 100)
        #expect(stops == 0)
    }

    @Test func `start works again after a stop`() {
        let timer = make()
        timer.start(.duration(5))
        run(timer, seconds: 6)
        timer.start(.duration(60))
        #expect(timer.state == .running(.duration(60)))
    }

    @Test(arguments: [(21, false), (22, true), (23, true), (0, true), (5, true), (6, false), (12, false)])
    func `night window wraps past midnight`(hour: Int, expected: Bool) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let date = Date(timeIntervalSince1970: TimeInterval(hour * 3600 + 60))
        #expect(NightTimer(startHour: 22, endHour: 6).contains(date, calendar: calendar) == expected)
    }

    @Test func `night window within one day`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let night = NightTimer(startHour: 1, endHour: 4)
        #expect(night.contains(Date(timeIntervalSince1970: 2 * 3600), calendar: calendar))
        #expect(!night.contains(Date(timeIntervalSince1970: 5 * 3600), calendar: calendar))
    }
}

@MainActor final class SleepTimerControllerTests {
    let engine = FakeEngine()
    var clock = Date(timeIntervalSince1970: 0)
    let book = Book(
        title: "One Part",
        files: [AudioFile(relativePath: "1.mp3", duration: 600, format: "mp3")],
        chapters: [Chapter(index: 0, title: "One", start: 0, end: 200), Chapter(index: 1, title: "Two", start: 200, end: 600)],
    )
    let folder = URL(filePath: "/tmp")

    private func loaded() async -> PlayerController {
        let player = PlayerController(engine: engine, now: { [unowned self] in clock })
        player.smartRewindEnabled = false
        await player.load(book, folder: folder)
        return player
    }

    /// Plays `seconds` of wall time in 0.5 s steps, like the engine's time observer.
    private func play(_ seconds: TimeInterval) {
        for _ in 0 ..< Int(seconds * 2) {
            clock += 0.5
            engine.advance(by: 0.5)
        }
    }

    @Test func `timer pauses playback and restores volume`() async {
        let player = await loaded()
        player.play()
        player.startSleepTimer(.duration(30))
        play(25)
        #expect(player.isPlaying)
        #expect(engine.volume < 1)
        play(5)
        #expect(!player.isPlaying)
        #expect(player.sleepTimer.state == .stopped)
        #expect(engine.volume == 1)
    }

    @Test func `end of chapter stops at the chapter end`() async {
        let player = await loaded()
        player.play()
        player.startSleepTimerAtChapterEnd()
        play(199)
        #expect(player.isPlaying)
        play(2)
        #expect(!player.isPlaying)
        #expect(player.position >= 200)
        #expect(player.position < 202)
    }

    @Test func `timer does not count while paused`() async {
        let player = await loaded()
        player.play()
        player.startSleepTimer(.duration(30))
        play(10)
        player.pause()
        clock += 3600
        player.play()
        play(5)
        #expect(player.isPlaying)
        #expect(player.sleepTimer.remaining == 15)
    }

    @Test func `night timer starts on play at night only`() async {
        let player = await loaded()
        player.nightTimer = NightTimer(startHour: 0, endHour: 24, minutes: 20)
        player.play()
        #expect(player.sleepTimer.state == .running(.duration(1200)))

        let day = await loaded()
        day.nightTimer = NightTimer(startHour: 5, endHour: 5, minutes: 20)
        day.play()
        #expect(day.sleepTimer.state == .off)
    }
}

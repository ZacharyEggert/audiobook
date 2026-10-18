import AudiobookCore
import Foundation
@testable import Playback
import Testing

@MainActor final class PlaybackSpeedTests {
    let engine = FakeEngine()
    let folder = URL(filePath: "/tmp")

    func book() -> Book {
        Book(
            title: "One Part",
            files: [AudioFile(relativePath: "1.mp3", duration: 120, format: "mp3")],
            chapters: [Chapter(index: 0, title: "One", start: 0, end: 120)],
        )
    }

    @Test(arguments: [(0.1, 0.5), (0.5, 0.5), (1.02, 1.0), (1.03, 1.05), (3.49, 3.5), (9.0, 3.5)] as [(Float, Float)])
    func `clamp snaps to the step and range`(input: Float, expected: Float) {
        #expect(PlaybackSpeed.clamp(input) == expected)
    }

    @Test func `every step is a fixed point of clamp`() {
        for steps in 10 ... 70 {
            let rate = Float(steps) / 20
            #expect(PlaybackSpeed.clamp(rate) == rate)
        }
    }

    @Test func `rate is clamped and reaches the engine`() async {
        let player = PlayerController(engine: engine)
        await player.load(book(), folder: folder)
        player.rate = 5
        #expect(player.rate == 3.5)
        #expect(engine.rate == 3.5)
    }

    @Test func `a new book gets the default rate`() async {
        let player = PlayerController(engine: engine)
        player.defaultRate = 1.5
        await player.load(book(), folder: folder)
        #expect(player.rate == 1.5)
        #expect(engine.rate == 1.5)
    }

    @Test func `a saved rate beats the default and loading it does not save`() async {
        let player = PlayerController(engine: engine)
        let book = book()
        var saves: [(UUID, Float)] = []
        player.defaultRate = 1.5
        player.savedRate = { $0 == book.id ? 2 : nil }
        player.onRateChange = { saves.append(($0, $1)) }
        await player.load(book, folder: folder)
        #expect(player.rate == 2)
        #expect(saves.isEmpty)
        player.rate = 1.25
        #expect(saves.count == 1)
        #expect(saves.first?.0 == book.id)
        #expect(saves.first?.1 == 1.25)
    }

    @Test func `switching books switches rates`() async {
        let player = PlayerController(engine: engine)
        let a = book(), b = book()
        let saved: [UUID: Float] = [a.id: 2]
        player.savedRate = { saved[$0] }
        await player.load(a, folder: folder)
        #expect(player.rate == 2)
        await player.load(b, folder: folder)
        #expect(player.rate == 1)
    }

    @Test func `a rebuilt engine gets the rate`() async {
        let fresh = FakeEngine()
        var engines = [engine, fresh]
        let player = PlayerController(makeEngine: { engines.removeFirst() })
        await player.load(book(), folder: folder)
        player.rate = 1.75
        await player.handle(.mediaServicesReset)
        #expect(fresh.rate == 1.75)
    }
}

import AudiobookCore
import Foundation
@testable import Playback
import Testing

@MainActor struct PlayerControllerTests {
    let engine = FakeEngine()
    let book = Book(
        title: "Two Parts",
        files: [
            AudioFile(relativePath: "1.mp3", duration: 60, format: "mp3"),
            AudioFile(relativePath: "2.mp3", duration: 60, format: "mp3"),
        ],
        chapters: [Chapter(index: 0, title: "One", start: 0, end: 60), Chapter(index: 1, title: "Two", start: 60, end: 120)],
    )

    @Test func `fake engine drives position and chapter`() async {
        let player = PlayerController(engine: engine)
        await player.load(book, folder: URL(filePath: "/tmp"), at: 50)
        #expect(player.chapter?.title == "One")
        player.play()
        engine.advance(by: 15)
        #expect(player.position == 65)
        #expect(player.chapter?.title == "Two")
    }
}

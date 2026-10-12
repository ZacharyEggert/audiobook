import Foundation
@testable import MediaParsing
import Testing

@Test func `parses book.cue`() throws {
    let sheet = try CueParser.parse(fixture("book.cue"))
    #expect(sheet.title == "Cue Fixture")
    #expect(sheet.performer == "Test Author")
    let chapters = [
        RawChapter(start: 0, title: "Part One"),
        RawChapter(start: 2, title: "Part Two"),
        RawChapter(start: 4 + 37.0 / 75, title: "Part Three"),
    ]
    #expect(sheet.files == [CueSheet.File(name: "book.mp3", chapters: chapters)])
}

@Test func `handles multiple files, CRLF, case and unquoted values`() {
    let text = """
    \u{FEFF}REM GENRE Audiobook\r
    performer Narrator\r
    title "Book"\r
    FILE disc1.mp3 MP3\r
      TRACK 01 AUDIO\r
        TITLE "One"\r
        PERFORMER "Track performer"\r
        INDEX 00 00:00:00\r
        INDEX 01 00:00:30\r
      TRACK 02 AUDIO\r
        INDEX 01 120:00:00\r
    FILE "disc 2.mp3" MP3\r
      TRACK 03 AUDIO\r
        TITLE "No index"\r
      TRACK 04 AUDIO\r
        TITLE "Unterminated\r
        INDEX 01 00:61:00\r
      TRACK 05 AUDIO\r
        TITLE Bare words\r
        INDEX 01 00:01:74\r
    """
    let sheet = CueParser.parse(text)
    #expect(sheet.title == "Book")
    #expect(sheet.performer == "Narrator")
    #expect(sheet.files == [
        CueSheet.File(name: "disc1.mp3", chapters: [RawChapter(start: 0.4, title: "One"), RawChapter(start: 7200, title: "")]),
        CueSheet.File(name: "disc 2.mp3", chapters: [RawChapter(start: 1 + 74.0 / 75, title: "Bare")]),
    ])
}

@Test func `ignores INDEX outside a FILE and TRACK`() {
    let sheet = CueParser.parse("INDEX 01 00:00:00\nTRACK 01 AUDIO\nINDEX 01 00:00:00\n")
    #expect(sheet.files.isEmpty)
}

@Test func `falls back to Windows-1252`() {
    let data = Data("TITLE \"Caf".utf8) + Data([0xE9, 0x22]) // é in Windows-1252, then the closing quote
    #expect(CueParser.parse(data).title == "Café")
}

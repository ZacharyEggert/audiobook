import Foundation
@testable import MediaParsing
import Testing

private let threeChapters = [
    RawChapter(start: 0, title: "Opening"),
    RawChapter(start: 2, title: "Middle"),
    RawChapter(start: 4.5, title: "Ending"),
]

/// What `MediaProbe` should report for one fixture. Nil fields aren't checked.
struct ProbeCase: CustomTestStringConvertible, Sendable {
    var file: String
    var format: ProbeResult.Format
    var duration: TimeInterval?
    var title: String?
    var trackTitle: String?
    var author: String?
    var narrator: String?
    var series: String?
    var year: Int?
    var trackNumber: Int?
    var discNumber: Int?
    var hasCover = false
    var chapters: [RawChapter] = []
    var chapterSource: ProbeResult.ChapterSource?

    var testDescription: String {
        file
    }
}

private let cases: [ProbeCase] = [
    ProbeCase(
        file: "chapters.m4b", format: .mp4, duration: 6, title: "Chapters Fixture",
        author: "Test Author", narrator: "Test Narrator", year: 2024, hasCover: true,
        chapters: threeChapters, chapterSource: .quickTime,
    ),
    ProbeCase(file: "both-chapters.m4b", format: .mp4, duration: 6, chapters: threeChapters, chapterSource: .quickTime),
    ProbeCase(
        file: "nero-chapters.m4b", format: .mp4, duration: 6, title: "Chapters Fixture", series: "Fixture Saga",
        chapters: threeChapters, chapterSource: .nero,
    ),
    ProbeCase(
        file: "chapters.mp3", format: .mp3, duration: 6, title: "Chapters Fixture", trackTitle: "Chapters Fixture",
        author: "Test Author", narrator: "Test Narrator", year: 2024, hasCover: true, chapters: threeChapters, chapterSource: .id3,
    ),
    ProbeCase(
        file: "chapters.flac", format: .flac, duration: 6, title: "Chapters Fixture", author: "Test Author",
        narrator: "Test Narrator", year: 2024, hasCover: true, chapters: threeChapters, chapterSource: .vorbis,
    ),
    ProbeCase(
        file: "book.mp3", format: .mp3, duration: 6.084, title: "Cue Fixture",
        chapters: [
            RawChapter(start: 0, title: "Part One"),
            RawChapter(start: 2, title: "Part Two"),
            RawChapter(start: 4 + 37.0 / 75, title: "Part Three"),
        ],
        chapterSource: .cue,
    ),
    ProbeCase(
        file: "overdrive.mp3", format: .mp3, duration: 6, title: "Überdrive Fixture", author: "Test Author",
        chapters: [
            RawChapter(start: 0, title: "Chapter 1"),
            RawChapter(start: 2.5, title: "Chapter 2"),
            RawChapter(start: 4, title: "Chapter 3"),
        ],
        chapterSource: .overDrive,
    ),
    ProbeCase(file: "vbr.mp3", format: .mp3, duration: 10),
    ProbeCase(
        file: "multi-mp3/Part 10.mp3", format: .mp3, duration: 2, title: "Multi MP3 Fixture", trackTitle: "Part Ten",
        trackNumber: 3,
    ),
    ProbeCase(
        file: "multi-disc/CD2/01.mp3", format: .mp3, duration: 2, title: "Multi Disc Fixture",
        trackTitle: "Disc 2 Track 1", trackNumber: 1, discNumber: 2,
    ),
]

@Test(arguments: cases)
func `probes fixture`(expected: ProbeCase) throws {
    let result = try MediaProbe.probe(fixtureURL(expected.file))
    #expect(result.format == expected.format)
    if let duration = expected.duration {
        #expect(try abs(#require(result.duration) - duration) < 0.5)
    }
    let fields: [(KeyPath<ProbeCase, String?>, KeyPath<ProbeResult, String?>)] = [
        (\.title, \.title), (\.trackTitle, \.trackTitle), (\.author, \.author), (\.narrator, \.narrator), (\.series, \.series),
    ]
    for (expectedField, resultField) in fields {
        if let value = expected[keyPath: expectedField] {
            #expect(result[keyPath: resultField] == value)
        }
    }
    if let year = expected.year {
        #expect(result.year == year)
    }
    if let track = expected.trackNumber {
        #expect(result.trackNumber == track)
    }
    if let disc = expected.discNumber {
        #expect(result.discNumber == disc)
    }
    #expect((result.cover != nil) == expected.hasCover)
    #expect(result.chapters == expected.chapters)
    #expect(result.chapterSource == expected.chapterSource)
}

@Test(arguments: ["corrupt.m4b", "book.zip", "book.cue", "multi-mp3/cover.jpg"])
func `rejects files that aren't parseable audio`(file: String) {
    #expect(throws: (any Error).self) { try MediaProbe.probe(fixtureURL(file)) }
}

@Test func `detects formats by signature`() throws {
    func format(_ bytes: [UInt8]) -> ProbeResult.Format? {
        MediaProbe.format(of: Data(bytes))
    }
    #expect(format(Array("RIFF\0\0\0\0WAVE".utf8)) == .wav)
    #expect(format(Array("FORM\0\0\0\0AIFC".utf8)) == .aiff)
    #expect(format(Array("caff\0\0\0\0".utf8)) == .caf)
    #expect(format([0xFF, 0xF1, 0x50, 0x80]) == .aac) // ADTS
    #expect(format([0xFF, 0xF3, 0x58, 0xC0]) == .mp3)
    #expect(format(Array("ID3".utf8) + [4, 0, 0, 0, 0, 0, 0] + Array("fLaC".utf8)) == .flac)
    #expect(format(Array("ID3".utf8) + [4, 0, 0, 0, 0, 0, 0] + [0xFF, 0xF1, 0x50, 0x80]) == .aac)
    #expect(format([0, 1, 2]) == nil)
    #expect(try MediaProbe.format(of: fixture("chapters.m4b")) == .mp4)
}

@Test func `parses OverDrive markers`() {
    let xml = """
    <Markers><Marker><Name> Intro &amp; Prologue </Name><Time>0:00.000</Time></Marker>
    <Marker>
      <Name>Part 2</Name>
      <Time>1:02:03.500</Time>
    </Marker><Marker><Name>Bad</Name><Time>soon</Time></Marker></Markers>
    """
    #expect(OverDriveMarkers.chapters(from: xml) == [
        RawChapter(start: 0, title: "Intro & Prologue"),
        RawChapter(start: 3723.5, title: "Part 2"),
    ])
}

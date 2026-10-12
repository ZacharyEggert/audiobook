import Foundation
@testable import MediaParsing
import Testing

private let fixtureChapters = [
    RawChapter(start: 0, title: "Opening"),
    RawChapter(start: 2, title: "Middle"),
    RawChapter(start: 4.5, title: "Ending"),
]

@Test func `parses chpl and freeform atoms`() throws {
    let result = try MP4Parser.parse(fixture("nero-chapters.m4b"))
    #expect(result.chapters == fixtureChapters)
    #expect(result.tags["©nam"] == "Chapters Fixture")
    #expect(result.tags["©alb"] == "Chapters Fixture")
    #expect(result.tags["©ART"] == "Test Author")
    #expect(result.tags["aART"] == "Test Author")
    #expect(result.tags["©wrt"] == "Test Narrator")
    #expect(result.tags["©gen"] == "Audiobook")
    #expect(result.tags["©day"] == "2024")
    #expect(result.tags["----:com.apple.iTunes:SERIES"] == "Fixture Saga")
    #expect(try abs(#require(result.duration) - 6) < 0.1)
    #expect(result.cover == nil)
}

@Test func `parses covr and ignores the QuickTime chapter track`() throws {
    let result = try MP4Parser.parse(fixture("chapters.m4b"))
    #expect(result.chapters.isEmpty) // chapter track is read through AVFoundation in Library
    #expect(result.tags["©nam"] == "Chapters Fixture")
    #expect(try #require(result.cover).prefix(2) == Data([0xFF, 0xD8])) // JPEG
}

@Test func `throws on truncated moov`() throws {
    #expect {
        try MP4Parser.parse(fixture("corrupt.m4b"))
    } throws: { error in
        if case ParseError.truncated = error {
            true
        } else {
            false
        }
    }
}

@Test func `throws when there is no moov`() throws {
    #expect(throws: ParseError.self) { try MP4Parser.parse(fixture("chapters.mp3")) }
    #expect(throws: ParseError.malformed("no moov box")) { try MP4Parser.parse(box("ftyp", Data("M4B ".utf8))) }
}

@Test func `throws on a box smaller than its header`() {
    var data = box("ftyp", Data())
    data.append(contentsOf: [0, 0, 0, 4] + Array("moov".utf8))
    #expect(throws: ParseError.malformed("moov box size 4 is smaller than its header")) { try MP4Parser.parse(data) }
}

@Test func `reads 64-bit, to-end and zero-terminated boxes`() throws {
    let mvhd = box("mvhd", Data([1, 0, 0, 0]) + Data(count: 16) + be32(1000) + be64(90500))
    let udta = box("udta", ilstMeta(item("©nam", data(type: 1, Data("Large".utf8)))) + Data(count: 4)) // QuickTime terminator
    var moov = Data(be32(1) + Array("moov".utf8))
    moov.append(be64(UInt64(16 + mvhd.count + udta.count)))
    moov.append(mvhd + udta)

    let result = try MP4Parser.parse(box("ftyp", Data()) + moov)
    #expect(result.duration == 90.5)
    #expect(result.tags["©nam"] == "Large")

    let toEnd = Data(be32(0) + Array("moov".utf8)) + mvhd
    #expect(try MP4Parser.parse(toEnd).duration == 90.5)
}

@Test func `reads QuickTime-style meta without version`() throws {
    let meta = box("meta", box("hdlr", Data(count: 25)) + box("ilst", item("©nam", data(type: 1, Data("QT".utf8)))))
    let result = try MP4Parser.parse(box("moov", box("udta", meta)))
    #expect(result.tags["©nam"] == "QT")
}

@Test func `decodes data atom types`() throws {
    let items = [
        item("trkn", data(type: 0, Data([0, 0, 0, 3, 0, 12, 0, 0]))),
        item("disk", data(type: 0, Data([0, 0, 0, 2, 0, 0]))),
        item("©nam", data(type: 2, Data([0x00, 0x48, 0x00, 0xE9]))), // UTF-16BE "Hé"
        item("tmpo", data(type: 21, Data([0xFF, 0xFE]))),
        item("rtng", data(type: 21, Data([1, 2, 3]))), // odd width: skipped
        item("©cmt", data(type: 1, Data("note\0".utf8))),
        item("©too", data(type: 99, Data("?".utf8))),
        item("covr", data(type: 14, Data([0x89, 0x50])) + data(type: 13, Data([0xFF, 0xD8]))),
    ]
    let result = try MP4Parser.parse(box("moov", box("udta", ilstMeta(items.reduce(Data(), +)))))
    #expect(result.tags == ["trkn": "3/12", "disk": "2", "©nam": "Hé", "tmpo": "-2", "©cmt": "note"])
    #expect(result.cover == Data([0x89, 0x50]))
}

@Test func `reads version 0 chpl`() throws {
    let chpl = box("chpl", Data([0, 0, 0, 0, 1]) + be64(15_000_000) + Data([2]) + Data("Hi".utf8))
    #expect(try MP4Parser.parse(box("moov", box("udta", chpl))).chapters == [RawChapter(start: 1.5, title: "Hi")])
}

/// Fuzz-style: every prefix of a real file either parses or throws.
@Test func `never traps on any prefix`() throws {
    let file = try fixture("nero-chapters.m4b")
    var parsed = 0
    for length in 0 ... file.count where (try? MP4Parser.parse(file.prefix(length))) != nil {
        parsed += 1
    }
    #expect(parsed == 1) // moov is last, so only the whole file is complete
}

// MARK: - Box builders

private func be32(_ value: UInt32) -> Data {
    withUnsafeBytes(of: value.bigEndian) { Data($0) }
}

private func be64(_ value: UInt64) -> Data {
    withUnsafeBytes(of: value.bigEndian) { Data($0) }
}

private func box(_ type: String, _ body: Data) -> Data {
    be32(UInt32(8 + body.count)) + Data(type.unicodeScalars.map { UInt8($0.value) }) + body
}

private func data(type: UInt32, _ value: Data) -> Data {
    box("data", be32(type) + Data(count: 4) + value)
}

private func item(_ key: String, _ children: Data) -> Data {
    box(key, children)
}

/// iTunes-style full-box `meta` (version/flags) wrapping `ilst`.
private func ilstMeta(_ items: Data) -> Data {
    box("meta", Data(count: 4) + box("hdlr", Data(count: 25)) + box("ilst", items))
}

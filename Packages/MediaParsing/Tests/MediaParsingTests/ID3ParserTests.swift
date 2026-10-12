import Foundation
@testable import MediaParsing
import Testing

@Test func `parses v2.4 chapters, text and cover`() throws {
    let file = try fixture("chapters.mp3")
    let tag = try #require(try ID3Parser.parse(file))
    #expect(tag.version == 4)
    #expect(tag.chapters == [
        RawChapter(start: 0, title: "Opening"),
        RawChapter(start: 2, title: "Middle"),
        RawChapter(start: 4.5, title: "Ending"),
    ])
    #expect(tag.tags["TIT2"] == "Chapters Fixture")
    #expect(tag.tags["TALB"] == "Chapters Fixture")
    #expect(tag.tags["TPE1"] == "Test Author")
    #expect(tag.tags["TPE2"] == "Test Author")
    #expect(tag.tags["TCOM"] == "Test Narrator")
    #expect(tag.tags["TDRC"] == "2024")
    #expect(try #require(tag.cover).prefix(2) == Data([0xFF, 0xD8]))
    #expect(file[tag.byteCount] == 0xFF) // MPEG frame sync right after the tag
}

@Test func `parses v2.3 UTF-16 text and OverDrive TXXX`() throws {
    let tag = try #require(try ID3Parser.parse(fixture("overdrive.mp3")))
    #expect(tag.version == 3)
    #expect(tag.tags["TIT2"] == "Überdrive Fixture")
    #expect(tag.tags["TRCK"] == "1")
    let markers = try #require(tag.tags["TXXX:OverDrive MediaMarkers"])
    #expect(markers.hasPrefix("<Markers><Marker><Name>Chapter 1</Name>"))
    #expect(tag.chapters.isEmpty)
}

@Test func `returns nil without an ID3 header`() throws {
    #expect(try ID3Parser.parse(fixture("chapters.m4b")) == nil)
    #expect(try ID3Parser.parse(Data("ID3".utf8)) == nil)
}

@Test func `rejects unknown major versions`() {
    #expect(throws: ParseError.malformed("unsupported ID3v2.5")) { try ID3Parser.parse(tag(version: 5, Data())) }
}

@Test func `undoes v2.3 whole-tag unsynchronisation`() throws {
    let frames = frame("TIT2", latin1Text(Data([0xFF, 0xFE])), version: 3) + frame("TPE1", latin1Text(Data([0xFF, 0x41])), version: 3)
    let parsed = try #require(try ID3Parser.parse(tag(version: 3, flags: 0x80, unsynchronise(frames))))
    #expect(parsed.tags == ["TIT2": "ÿþ", "TPE1": "ÿA"])
}

@Test func `handles v2.4 frame flags`() throws {
    let unsyncBody = Data([0x00, 0xFF, 0x00, 0xFE]) // Latin-1 "ÿþ" with FF 00
    let frames = frame("TPE1", unsyncBody, flags: 0x0002)
        + frame("TALB", Data([0, 0, 0, 3]) + text3("Album"), flags: 0x0001) // data length indicator
        + frame("TCON", Data([7]) + text3("Genre"), flags: 0x0040) // group ID
        + frame("TIT2", text3("Squashed"), flags: 0x0008) // compressed: skipped
        + frame("TCOM", text3("Narrator"))
    let parsed = try #require(try ID3Parser.parse(tag(version: 4, frames)))
    #expect(parsed.tags == ["TPE1": "ÿþ", "TALB": "Album", "TCON": "Genre", "TCOM": "Narrator"])
}

@Test func `handles v2.4 tag-level unsynchronisation and footer`() throws {
    let parsed = try #require(try ID3Parser.parse(tag(version: 4, flags: 0x90, frame("TPE1", Data([0x00, 0xFF, 0x00, 0x41])))))
    #expect(parsed.tags["TPE1"] == "ÿA")
    #expect(parsed.byteCount == 10 + 14 + 10)
}

@Test func `skips extended headers`() throws {
    let extendedV3 = Data([0, 0, 0, 6]) + Data(count: 6) + frame("TIT2", text3("Three"), version: 3)
    #expect(try ID3Parser.parse(tag(version: 3, flags: 0x40, extendedV3))?.tags["TIT2"] == "Three")
    let extendedV4 = syncsafe(6) + Data([1, 0]) + frame("TIT2", text3("Four"))
    #expect(try ID3Parser.parse(tag(version: 4, flags: 0x40, extendedV4))?.tags["TIT2"] == "Four")
}

@Test func `reads iTunes non-syncsafe v2.4 frame sizes`() throws {
    let value = text3(String(repeating: "a", count: 200))
    var raw = Data("TIT2".utf8) + be32(UInt32(value.count)) + Data([0, 0]) + value // 201 = 0x000000C9, high bit set
    raw += frame("TPE1", text3("After"))
    let parsed = try #require(try ID3Parser.parse(tag(version: 4, raw)))
    #expect(parsed.tags["TIT2"]?.count == 200)
    #expect(parsed.tags["TPE1"] == "After")
}

@Test func `decodes every text encoding and multiple values`() throws {
    let frames = frame("TIT2", Data([0]) + Data("Caf\u{E9}".unicodeScalars.map { UInt8($0.value) }))
        + frame("TPE1", Data([1, 0xFF, 0xFE, 0x41, 0, 0, 0, 0xFF, 0xFE, 0x42, 0])) // UTF-16 LE, two values
        + frame("TPE2", Data([1, 0xFE, 0xFF, 0, 0x43])) // UTF-16 BE BOM
        + frame("TCOM", Data([2, 0, 0x44, 0, 0x45])) // UTF-16BE
        + frame("TALB", text3("One\u{0}Two\u{0}"))
        + frame("MVNM", text3("Saga"))
        + frame("WXXX", text3("ignored"))
        + Data(count: 20) // padding
    let parsed = try #require(try ID3Parser.parse(tag(version: 4, frames)))
    #expect(parsed.tags == ["TIT2": "Café", "TPE1": "A; B", "TPE2": "C", "TCOM": "DE", "TALB": "One; Two", "MVNM": "Saga"])
}

@Test func `reads TXXX and COMM descriptions`() throws {
    let frames = frame("TXXX", text3("SERIES\u{0}Saga"))
        + frame("COMM", Data([3]) + Data("eng".utf8) + Data("\u{0}A comment".utf8))
        + frame("COMM", Data([3]) + Data("deu".utf8) + Data("\u{0}Second".utf8))
        + frame("COMM", Data([1]) + Data("eng".utf8) + Data([0xFF, 0xFE, 0x78, 0, 0, 0, 0xFF, 0xFE, 0x79, 0]))
    let parsed = try #require(try ID3Parser.parse(tag(version: 4, frames)))
    #expect(parsed.tags == ["TXXX:SERIES": "Saga", "COMM": "A comment", "COMM:x": "y"])
}

@Test func `prefers the front cover`() throws {
    let other = frame("APIC", Data([0]) + Data("image/png\u{0}".utf8) + Data([4]) + Data("back\u{0}".utf8) + Data([1, 2]), version: 3)
    let front = frame("APIC", Data([1]) + Data("image/jpeg\u{0}".utf8) + Data([3, 0xFF, 0xFE, 0, 0]) + Data([3, 4]), version: 3)
    let parsed = try #require(try ID3Parser.parse(tag(version: 3, other + front)))
    #expect(parsed.cover == Data([3, 4]))
    let onlyOther = try #require(try ID3Parser.parse(tag(version: 3, other)))
    #expect(onlyOther.cover == Data([1, 2]))
}

@Test func `maps v2.2 frames`() throws {
    func frame22(_ id: String, _ body: Data) -> Data {
        Data(id.utf8) + Data([0, 0, UInt8(body.count)]) + body
    }
    let frames = frame22("TT2", text3("Old")) + frame22("TP1", text3("Author"))
        + frame22("PIC", Data([0]) + Data("JPG".utf8) + Data([3, 0]) + Data([9, 9]))
    let parsed = try #require(try ID3Parser.parse(tag(version: 2, frames)))
    #expect(parsed.tags == ["TIT2": "Old", "TPE1": "Author"])
    #expect(parsed.cover == Data([9, 9]))
}

@Test func `orders chapters by top-level CTOC, else by start`() throws {
    func chap(_ id: String, _ startMs: UInt32, _ title: String) -> Data {
        frame("CHAP", Data(id.utf8) + Data([0]) + be32(startMs) + be32(0) + Data(repeating: 0xFF, count: 8) + frame("TIT2", text3(title)))
    }
    let chapters = chap("b", 5000, "Second") + chap("a", 0, "First") + chap("c", 9000, "Hidden")
    let sorted = try #require(try ID3Parser.parse(tag(version: 4, chapters)))
    #expect(sorted.chapters.map(\.title) == ["First", "Second", "Hidden"])

    let nested = frame("CTOC", Data("sub\u{0}".utf8) + Data([0x01, 1]) + Data("c\u{0}".utf8))
    let top = frame("CTOC", Data("toc\u{0}".utf8) + Data([0x03, 2]) + Data("b\u{0}a\u{0}".utf8))
    let ordered = try #require(try ID3Parser.parse(tag(version: 4, nested + top + chapters)))
    #expect(ordered.chapters == [RawChapter(start: 5, title: "Second"), RawChapter(start: 0, title: "First")])
}

/// Fuzz-style: every prefix of a real tag either parses or throws.
@Test func `ID3 never traps on any prefix`() throws {
    for name in ["chapters.mp3", "overdrive.mp3"] {
        let file = try fixture(name)
        let tagLength = try #require(try ID3Parser.parse(file)).byteCount
        var parsed = 0
        for length in 0 ... tagLength where (try? ID3Parser.parse(file.prefix(length))) != nil {
            parsed += 1
        }
        #expect(parsed == 1)
    }
}

// MARK: - Tag builders

private func be32(_ value: UInt32) -> Data {
    withUnsafeBytes(of: value.bigEndian) { Data($0) }
}

private func syncsafe(_ value: Int) -> Data {
    Data([3, 2, 1, 0].map { UInt8(value >> ($0 * 7) & 0x7F) })
}

/// UTF-8 text frame body.
private func text3(_ text: String) -> Data {
    Data([3]) + Data(text.utf8)
}

/// Latin-1 text frame body from raw bytes.
private func latin1Text(_ bytes: Data) -> Data {
    Data([0]) + bytes
}

private func frame(_ id: String, _ body: Data, version: UInt8 = 4, flags: UInt16 = 0) -> Data {
    let size = version == 4 ? syncsafe(body.count) : be32(UInt32(body.count))
    return Data(id.utf8) + size + Data([UInt8(flags >> 8), UInt8(flags & 0xFF)]) + body
}

/// Inserts `00` after every `FF`.
private func unsynchronise(_ data: Data) -> Data {
    data.reduce(into: Data()) { output, byte in
        output.append(byte)
        if byte == 0xFF {
            output.append(0)
        }
    }
}

private func tag(version: UInt8, flags: UInt8 = 0, _ body: Data) -> Data {
    Data("ID3".utf8) + Data([version, 0, flags]) + syncsafe(body.count) + body
}

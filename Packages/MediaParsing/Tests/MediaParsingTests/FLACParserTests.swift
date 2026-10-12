import Foundation
@testable import MediaParsing
import Testing

@Test func `parses FLAC chapters, comments, picture and duration`() throws {
    let result = try FLACParser.parse(fixture("chapters.flac"))
    #expect(result.chapters == [
        RawChapter(start: 0, title: "Opening"),
        RawChapter(start: 2, title: "Middle"),
        RawChapter(start: 4.5, title: "Ending"),
    ])
    #expect(result.tags == [
        "TITLE": "Chapters Fixture", "ALBUM": "Chapters Fixture", "ARTIST": "Test Author", "ALBUMARTIST": "Test Author",
        "COMPOSER": "Test Narrator", "GENRE": "Audiobook", "DATE": "2024",
    ])
    #expect(try #require(result.cover).prefix(2) == Data([0xFF, 0xD8]))
    #expect(result.duration == 6)
}

@Test func `throws without a fLaC marker`() throws {
    #expect(throws: ParseError.malformed("no fLaC marker")) { try FLACParser.parse(fixture("chapters.m4b")) }
    #expect(throws: ParseError.malformed("no fLaC marker")) { try FLACParser.parse(Data()) }
}

@Test func `reads comment pictures, repeated keys and odd chapters`() throws {
    let backPicture = picture(type: 4, Data([1]))
    let frontPicture = picture(type: 3, Data([2]))
    let comments = vorbisComments([
        "Artist=One", "ARTIST=Two", "EMPTY=", "no equals sign",
        "METADATA_BLOCK_PICTURE=\(frontPicture.base64EncodedString())", "METADATA_BLOCK_PICTURE=%%%",
        "CHAPTER10=01:00:00.5", "CHAPTER10NAME=Late", "CHAPTER2=90.25", "CHAPTER3NAME=No start",
        "CHAPTER+4=00:01", "CHAPTERS=x", "CHAPTER5=bad",
    ])
    let data = Data("fLaC".utf8) + block(6, backPicture) + block(4, comments) + block(1, Data(count: 4), isLast: true)
    let result = try FLACParser.parse(data)
    #expect(result.tags == ["ARTIST": "One; Two", "CHAPTER+4": "00:01", "CHAPTERS": "x"])
    #expect(result.cover == Data([2]))
    #expect(result.chapters == [RawChapter(start: 90.25, title: ""), RawChapter(start: 3600.5, title: "Late")])
    #expect(result.duration == nil)
}

@Test func `skips a leading ID3v2 tag`() throws {
    let id3 = Data("ID3".utf8) + Data([3, 0, 0, 0, 0, 0, 4]) + Data(count: 4)
    let data = id3 + Data("fLaC".utf8) + block(4, vorbisComments(["TITLE=Tagged"]), isLast: true)
    #expect(try FLACParser.parse(data).tags == ["TITLE": "Tagged"])
}

/// Fuzz-style: every prefix of a real file either parses or throws.
@Test func `FLAC never traps on any prefix`() throws {
    let file = try fixture("chapters.flac")
    for length in 0 ... 1000 {
        _ = try? FLACParser.parse(file.prefix(length))
    }
}

// MARK: - Block builders

private func block(_ type: UInt8, _ body: Data, isLast: Bool = false) -> Data {
    Data([type | (isLast ? 0x80 : 0), UInt8(body.count >> 16), UInt8(body.count >> 8 & 0xFF), UInt8(body.count & 0xFF)]) + body
}

private func le32(_ value: Int) -> Data {
    withUnsafeBytes(of: UInt32(value).littleEndian) { Data($0) }
}

private func be32(_ value: Int) -> Data {
    withUnsafeBytes(of: UInt32(value).bigEndian) { Data($0) }
}

private func vorbisComments(_ comments: [String]) -> Data {
    comments.reduce(le32(6) + Data("vendor".utf8) + le32(comments.count)) { $0 + le32($1.utf8.count) + Data($1.utf8) }
}

private func picture(type: Int, _ image: Data) -> Data {
    be32(type) + be32(10) + Data("image/jpeg".utf8) + be32(0) + Data(count: 16) + be32(image.count) + image
}

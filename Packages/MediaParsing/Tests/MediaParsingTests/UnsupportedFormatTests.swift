import Foundation
@testable import MediaParsing
import Testing

private func oggPage(_ packet: String) -> Data {
    // capture pattern, version, header type, granule (8), serial (4), sequence (4), CRC (4), 1 segment
    Data("OggS".utf8) + Data(count: 22) + Data([1, UInt8(packet.utf8.count)]) + Data(packet.utf8)
}

private let asfGUID = Data([0x30, 0x26, 0xB2, 0x75, 0x8E, 0x66, 0xCF, 0x11, 0xA6, 0xD9, 0x00, 0xAA, 0x00, 0x62, 0xCE, 0x6C])

/// A file's first bytes and its extension.
struct Sample: Sendable {
    var head: Data
    var pathExtension: String
}

@Test(arguments: [
    (Sample(head: Data(count: 4) + Data("ftypaax ".utf8), pathExtension: "m4b"), UnsupportedFormat.audible), // by brand
    (Sample(head: Data(), pathExtension: "AAX"), .audible), // by extension
    (Sample(head: Data(), pathExtension: "aaxc"), .audible),
    (Sample(head: oggPage("OpusHead"), pathExtension: "opus"), .opus),
    (Sample(head: oggPage("\u{1}vorbis"), pathExtension: "ogg"), .oggVorbis),
    (Sample(head: Data("OggS".utf8), pathExtension: "ogg"), .oggVorbis), // too short to name the codec
    (Sample(head: asfGUID + Data(count: 8), pathExtension: "wma"), .wma),
])
func `detects unsupported formats`(sample: Sample, expected: UnsupportedFormat) {
    #expect(UnsupportedFormat.detect(sample.head, pathExtension: sample.pathExtension) == expected)
}

@Test func `passes supported formats through`() throws {
    for name in ["chapters.m4b", "chapters.mp3", "chapters.flac", "corrupt.m4b"] {
        #expect(try UnsupportedFormat.detect(fixture(name), pathExtension: "m4b") == nil)
    }
}

@Test func `probe throws the reason`() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).opus")
    try oggPage("OpusHead").write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(throws: UnsupportedFormat.opus) { try MediaProbe.probe(url) }
    #expect(UnsupportedFormat.opus.reason == "Opus files aren't supported yet.")
}

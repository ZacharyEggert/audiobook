import Foundation
@testable import MediaParsing
import Testing

@Test(arguments: [
    ("vbr.mp3", 10.0), // Xing
    ("chapters.mp3", 6.0), // Info (CBR Xing)
    ("book.mp3", 6.084), // no header: CBR fallback
    ("multi-mp3/Part 1.mp3", 2.0),
])
func `matches ffprobe duration`(name: String, expected: TimeInterval) throws {
    let data = try fixture(name)
    let audioStart = try ID3Parser.parse(data)?.byteCount ?? 0
    #expect(try abs(MP3Duration.duration(of: data, audioStart: audioStart) - expected) < 0.5)
}

// MPEG-1 layer III, 128 kbit/s, 44.1 kHz: 417-byte frames of 1152 samples
private let stereoHeader: [UInt8] = [0xFF, 0xFB, 0x90, 0x00]
private let monoHeader: [UInt8] = [0xFF, 0xFB, 0x90, 0xC0]

private func frame(_ header: [UInt8], tagAt offset: Int = 0, _ tag: Data = Data()) -> Data {
    var data = Data(header) + Data(count: 413)
    data.replaceSubrange(offset ..< offset + tag.count, with: tag)
    return data
}

private func be32(_ value: UInt32) -> Data {
    withUnsafeBytes(of: value.bigEndian) { Data($0) }
}

@Test func `reads VBRI frame count`() throws {
    let vbri = Data("VBRI".utf8) + Data([0, 1, 0, 0, 0, 0]) + be32(0) + be32(100)
    let data = frame(stereoHeader, tagAt: 36, vbri) + frame(stereoHeader)
    #expect(try MP3Duration.duration(of: data) == 100 * 1152 / 44100)
}

@Test func `reads Xing after mono MPEG-1 side info`() throws {
    let xing = Data("Xing".utf8) + be32(0x1) + be32(50)
    let data = frame(monoHeader, tagAt: 4 + 17, xing) + frame(monoHeader)
    #expect(try MP3Duration.duration(of: data) == 50 * 1152 / 44100)
}

@Test func `falls back to bitrate when Xing has no frame count`() throws {
    let xing = Data("Xing".utf8) + be32(0x2) + be32(999)
    let data = frame(stereoHeader, tagAt: 36, xing) + frame(stereoHeader)
    #expect(try MP3Duration.duration(of: data) == TimeInterval(2 * 417 * 8) / 128_000)
}

@Test func `excludes the ID3v1 trailer and skips junk before the audio`() throws {
    let falseSync = Data(stereoHeader) + Data(count: 20) // valid header, but no frame where the next should be
    let frames = (0 ..< 10).reduce(Data()) { data, _ in data + frame(stereoHeader) }
    let trailer = Data("TAG".utf8) + Data(count: 125)
    let duration = try MP3Duration.duration(of: Data([1, 2, 3]) + falseSync + frames + trailer, audioStart: 3)
    #expect(duration == TimeInterval(10 * 417 * 8) / 128_000)
}

@Test func `throws without an MPEG frame`() throws {
    #expect(throws: ParseError.malformed("no MPEG audio frame")) { try MP3Duration.duration(of: Data(count: 1000)) }
    #expect(throws: ParseError.malformed("no MPEG audio frame")) { try MP3Duration.duration(of: Data(), audioStart: 5) }
    #expect(throws: ParseError.malformed("no MPEG audio frame")) { try MP3Duration.duration(of: fixture("chapters.flac")) }
}

@Test(arguments: [
    ([0xFF, 0xFB, 0x00, 0x00], false), // free bitrate
    ([0xFF, 0xFB, 0xF0, 0x00], false), // bitrate index 15
    ([0xFF, 0xFB, 0x9C, 0x00], false), // sample rate index 3
    ([0xFF, 0xEB, 0x90, 0x00], false), // reserved version
    ([0xFF, 0xF9, 0x90, 0x00], false), // reserved layer
    ([0xFF, 0xF3, 0x58, 0xC0], true), // MPEG-2 layer III (the fixtures)
    ([0xFF, 0xE3, 0x58, 0xC0], true), // MPEG-2.5
    ([0xFF, 0xFD, 0x90, 0x00], true), // MPEG-1 layer II
    ([0xFF, 0xFF, 0x90, 0x00], true), // MPEG-1 layer I
] as [([UInt8], Bool)])
func `validates frame headers`(bytes: [UInt8], valid: Bool) {
    #expect((FrameHeader(Data(bytes), at: 0) != nil) == valid)
}

@Test func `computes frame sizes per version and layer`() throws {
    let mpeg2 = try #require(FrameHeader(Data([0xFF, 0xF3, 0x58, 0xC0]), at: 0)) // 40 kbit/s, 16 kHz
    #expect(mpeg2.sampleRate == 16000)
    #expect(mpeg2.samplesPerFrame == 576)
    #expect(mpeg2.frameLength == 72 * 40000 / 16000)
    let layer1 = try #require(FrameHeader(Data([0xFF, 0xFF, 0x92, 0x00]), at: 0)) // 288 kbit/s, 44.1 kHz, padded
    #expect(layer1.frameLength == (12 * 288_000 / 44100 + 1) * 4)
    #expect(try #require(FrameHeader(Data([0xFF, 0xE3, 0x58, 0xC0]), at: 0)).sampleRate == 8000)
}

/// Fuzz-style: every prefix of a real file either gives a duration or throws.
@Test func `MP3 never traps on any prefix`() throws {
    let file = try fixture("vbr.mp3")
    for length in 0 ... 2000 {
        _ = try? MP3Duration.duration(of: file.prefix(length), audioStart: 20)
    }
}

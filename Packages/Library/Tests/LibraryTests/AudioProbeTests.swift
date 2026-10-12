import Foundation
@testable import Library
import MediaParsing
import Testing

@Test func `prefers the QuickTime chapter track`() async throws {
    let result = try await AudioProbe.probe(fixture("chapters.m4b"))
    #expect(result.chapterSource == .quickTime)
    #expect(result.chapters.map(\.title) == ["Opening", "Middle", "Ending"])
}

@Test func `keeps MediaProbe chapters when there is no track`() async throws {
    #expect(try await AudioProbe.probe(fixture("nero-chapters.m4b")).chapterSource == .nero)
    #expect(try await AudioProbe.probe(fixture("chapters.mp3")).chapterSource == .id3)
}

@Test func `fills duration through AVFoundation`() async throws {
    func le(_ value: some FixedWidthInteger) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
    let samples = Data(count: 16000) // 1 s of 8 kHz mono 16-bit silence
    let parts: [Data] = [
        Data("RIFF".utf8), le(UInt32(36 + samples.count)), Data("WAVEfmt ".utf8), le(UInt32(16)),
        le(UInt16(1)), le(UInt16(1)), le(UInt32(8000)), le(UInt32(16000)), le(UInt16(2)), le(UInt16(16)), // PCM, mono, rates, 16-bit
        Data("data".utf8), le(UInt32(samples.count)), samples,
    ]
    let wav = parts.reduce(Data(), +)
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).wav")
    try wav.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let result = try await AudioProbe.probe(url)
    #expect(result.format == .wav)
    #expect(try abs(#require(result.duration) - 1) < 0.01)
}

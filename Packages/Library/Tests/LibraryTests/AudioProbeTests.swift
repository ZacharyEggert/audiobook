import AVFoundation
@testable import Library
import MediaParsing
import Testing

/// AVFoundation's reading of a file's QuickTime chapter track, as an oracle for `MP4Parser`.
private func avFoundationChapters(of url: URL) async throws -> [RawChapter] {
    let asset = AVURLAsset(url: url)
    let locale = try await asset.load(.availableChapterLocales).first ?? Locale(identifier: "und")
    var chapters: [RawChapter] = []
    for group in try await asset.loadChapterMetadataGroups(withTitleLocale: locale, containingItemsWithCommonKeys: []) {
        let titleItem = AVMetadataItem.metadataItems(from: group.items, filteredByIdentifier: .commonIdentifierTitle).first
        try await chapters.append(RawChapter(start: group.timeRange.start.seconds, title: titleItem?.load(.stringValue) ?? ""))
    }
    return chapters
}

@Test(arguments: ["chapters.m4b", "both-chapters.m4b", "nero-chapters.m4b"])
func `chapter track parse matches AVFoundation`(file: String) async throws {
    let expected = try await avFoundationChapters(of: fixture(file))
    let result = try await AudioProbe.probe(fixture(file))
    #expect(try MP4Parser.parse(Data(contentsOf: fixture(file))).trackChapters == expected)
    #expect(result.chapterSource == (expected.isEmpty ? .nero : .quickTime))
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

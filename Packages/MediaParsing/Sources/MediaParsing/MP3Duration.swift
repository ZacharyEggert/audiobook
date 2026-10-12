import Foundation

/// Duration of an MPEG audio (MP3) stream from its first frame: the Xing/Info or VBRI frame count when
/// present, else file size over bitrate (exact for CBR, an estimate for VBR without a header).
/// ponytail: ignores the LAME encoder delay/padding (< 0.1 s); add it if gapless precision ever matters.
public enum MP3Duration {
    /// - Parameter audioStart: where audio begins, i.e. the ID3v2 tag's `byteCount` (0 if untagged).
    public static func duration(of data: Data, audioStart: Int = 0) throws(ParseError) -> TimeInterval {
        guard let (offset, header) = firstFrame(in: data, from: audioStart) else {
            throw .malformed("no MPEG audio frame")
        }
        // A frame too short to hold a header just means there isn't one
        if let frames = try? vbrFrameCount(in: data, at: offset, header: header), frames > 0 {
            return TimeInterval(frames) * TimeInterval(header.samplesPerFrame) / TimeInterval(header.sampleRate)
        }
        let hasID3v1 = data.count - offset >= 128 && data.suffix(128).starts(with: Data("TAG".utf8))
        let audioBytes = data.count - offset - (hasID3v1 ? 128 : 0)
        return TimeInterval(audioBytes) * 8 / TimeInterval(header.bitrate)
    }

    /// First offset holding a valid header whose following frame also starts with one (or runs to the end).
    /// The second check rejects stray `FF Ex` bytes in junk before the audio.
    private static func firstFrame(in data: Data, from start: Int) -> (Int, FrameHeader)? {
        let searchEnd = min(data.count - 4, start + 64 * 1024)
        guard start >= 0, start <= searchEnd else { return nil }
        for offset in start ... searchEnd {
            guard let header = FrameHeader(data, at: offset) else { continue }
            let next = offset + header.frameLength
            if next + 4 > data.count || FrameHeader(data, at: next) != nil {
                return (offset, header)
            }
        }
        return nil
    }

    /// Frame count from a Xing/Info header (after the side info) or a VBRI header (always 32 bytes in).
    private static func vbrFrameCount(in data: Data, at offset: Int, header: FrameHeader) throws(ParseError) -> UInt32? {
        var reader = ByteReader(data)
        try reader.skip(offset + 4 + header.sideInfoSize)
        if reader.remaining >= 12, try ["Xing", "Info"].contains(reader.readBytes(4).latin1) {
            let flags: UInt32 = try reader.read()
            return flags & 0x1 != 0 ? try reader.read() : nil
        }
        reader = ByteReader(data)
        try reader.skip(offset + 4 + 32)
        if reader.remaining >= 18, try reader.readBytes(4).latin1 == "VBRI" {
            try reader.skip(10) // version, delay, quality, byte count
            return try reader.read()
        }
        return nil
    }
}

struct FrameHeader: Equatable {
    var bitrate: Int // bits per second
    var sampleRate: Int
    var samplesPerFrame: Int
    var frameLength: Int
    var sideInfoSize: Int

    // Rows: MPEG-1 layer I, II, III; MPEG-2/2.5 layer I, then II and III. In kbit/s; index 0 (free) and 15 are invalid.
    private static let bitrates: [[Int]] = [
        [0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448],
        [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384],
        [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320],
        [0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256],
        [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
    ]

    /// Parses the 4-byte header at `offset`; nil if it isn't a valid MPEG audio frame header.
    init?(_ data: Data, at offset: Int) {
        var reader = ByteReader(data)
        guard (try? reader.skip(offset)) != nil, let raw = try? reader.read(UInt32.self) else { return nil }
        let versionBits = raw >> 19 & 0x3 // 0 = MPEG-2.5, 1 reserved, 2 = MPEG-2, 3 = MPEG-1
        let layer = 4 - Int(raw >> 17 & 0x3) // bits 3, 2, 1 = layer I, II, III; 0 reserved
        let bitrateIndex = Int(raw >> 12 & 0xF)
        let sampleRateIndex = Int(raw >> 10 & 0x3)
        guard raw >> 21 == 0x7FF, versionBits != 1, layer != 4, (1 ... 14).contains(bitrateIndex), sampleRateIndex != 3 else {
            return nil
        }
        let isMPEG1 = versionBits == 3
        let padding = Int(raw >> 9 & 0x1)
        let isMono = raw >> 6 & 0x3 == 3

        let row = isMPEG1 ? layer - 1 : min(layer + 2, 4)
        bitrate = Self.bitrates[row][bitrateIndex] * 1000
        sampleRate = [44100, 48000, 32000][sampleRateIndex] >> (isMPEG1 ? 0 : versionBits == 2 ? 1 : 2)
        samplesPerFrame = switch layer {
        case 1: 384
        case 2: 1152
        default: isMPEG1 ? 1152 : 576
        }
        frameLength = layer == 1
            ? (12 * bitrate / sampleRate + padding) * 4
            : samplesPerFrame / 8 * bitrate / sampleRate + padding
        sideInfoSize = switch (isMPEG1, isMono) {
        case (true, true): 17
        case (true, false): 32
        case (false, true): 9
        case (false, false): 17
        }
    }
}

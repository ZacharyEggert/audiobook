import Foundation

public struct ID3Metadata: Equatable, Sendable {
    /// Major version: 2, 3 or 4.
    public var version: UInt8
    /// Length of the whole tag, header and footer included. MPEG audio starts at this offset.
    public var byteCount: Int
    /// Text frames keyed by frame ID (`TIT2`, `TPE1`; v2.2 IDs mapped to v2.3), `TXXX:<description>`,
    /// and `COMM` or `COMM:<description>`. Multiple values in one frame are joined with `"; "`.
    public var tags: [String: String] = [:]
    /// Front cover if there is one, else the first picture.
    public var cover: Data?
    /// `CHAP` frames, in top-level `CTOC` order if present, else by start time.
    public var chapters: [RawChapter] = []
}

/// Reads an ID3v2.2/2.3/2.4 tag from the start of a file.
public enum ID3Parser {
    /// Returns nil when `data` doesn't start with an ID3v2 tag.
    public static func parse(_ data: Data) throws(ParseError) -> ID3Metadata? {
        var reader = ByteReader(data)
        guard data.count >= 10, try reader.readBytes(3) == Data("ID3".utf8) else { return nil }
        let version: UInt8 = try reader.read()
        try reader.skip(1) // revision
        let flags: UInt8 = try reader.read()
        let size = try Int(reader.readSyncsafeUInt32())
        guard (2 ... 4).contains(version) else { throw .malformed("unsupported ID3v2.\(version)") }

        let hasFooter = version == 4 && flags & 0x10 != 0
        var result = ID3Metadata(version: version, byteCount: 10 + size + (hasFooter ? 10 : 0))
        var body = try reader.readBytes(size)
        let unsynchronised = flags & 0x80 != 0
        // Before v2.4 unsynchronisation covers the whole tag; v2.4 applies it per frame
        if unsynchronised, version < 4 {
            body = resync(body)
        }
        if version == 2, flags & 0x40 != 0 {
            return result // v2.2 compression never had a defined scheme
        }

        var frames = ByteReader(body)
        if version > 2, flags & 0x40 != 0 {
            try skipExtendedHeader(&frames, version: version)
        }
        let parsed = try parseFrames(&frames, version: version, unsynchronised: unsynchronised && version == 4)
        result.tags = parsed.tags
        result.cover = parsed.cover
        result.chapters = parsed.orderedChapters
        return result
    }

    private static func skipExtendedHeader(_ reader: inout ByteReader, version: UInt8) throws(ParseError) {
        if version == 3 {
            try reader.skip(Int(reader.read(UInt32.self))) // size excludes itself
        } else {
            let size = try Int(reader.readSyncsafeUInt32()) // size includes itself
            guard size >= 4 else { throw .malformed("extended header size \(size)") }
            try reader.skip(size - 4)
        }
    }

    // MARK: - Frames

    private struct Frames {
        var tags: [String: String] = [:]
        var cover: Data?
        var hasFrontCover = false
        var chapters: [(id: String, chapter: RawChapter)] = []
        var tableOfContents: [String]?

        var orderedChapters: [RawChapter] {
            if let tableOfContents {
                let byID = Dictionary(chapters.map { ($0.id, $0.chapter) }, uniquingKeysWith: { first, _ in first })
                let ordered = tableOfContents.compactMap { byID[$0] }
                if !ordered.isEmpty {
                    return ordered
                }
            }
            return chapters.map(\.chapter).sorted { $0.start < $1.start }
        }
    }

    private static let v22IDs = [
        "TT2": "TIT2", "TAL": "TALB", "TP1": "TPE1", "TP2": "TPE2", "TCM": "TCOM", "TYE": "TYER", "TCO": "TCON",
        "TPB": "TPUB", "TRK": "TRCK", "TPA": "TPOS", "TXX": "TXXX", "COM": "COMM",
    ]

    private static func parseFrames(_ reader: inout ByteReader, version: UInt8, unsynchronised: Bool) throws(ParseError) -> Frames {
        var frames = Frames()
        let idLength = version == 2 ? 3 : 4
        while reader.remaining >= (version == 2 ? 6 : 10) {
            let idBytes = try reader.readBytes(idLength)
            guard idBytes.first != 0 else { break } // padding
            let id = idBytes.latin1
            let size = switch version {
            case 2: try Int(reader.readUInt24())
            case 3: try Int(reader.read(UInt32.self))
            default: try v24FrameSize(&reader)
            }
            let flags: UInt16 = version == 2 ? 0 : try reader.read()
            let body = try reader.readBytes(size)
            guard let data = frameData(body, flags: flags, version: version, unsynchronised: unsynchronised) else { continue }
            try handleFrame(version == 2 ? v22IDs[id] ?? id : id, data, version: version, into: &frames)
        }
        return frames
    }

    /// v2.4 sizes are syncsafe, but iTunes wrote plain integers. A high bit set in any byte means a plain one.
    /// ponytail: a plain size with no high bits set (e.g. 256) still reads as syncsafe; checking that the
    /// next frame ID is valid under each reading (as mutagen does) would catch those too.
    private static func v24FrameSize(_ reader: inout ByteReader) throws(ParseError) -> Int {
        var peek = reader
        let raw: UInt32 = try peek.read()
        return raw & 0x8080_8080 != 0 ? try Int(reader.read(UInt32.self)) : try Int(reader.readSyncsafeUInt32())
    }

    /// Strips per-frame prefixes and undoes unsynchronisation. Nil for compressed or encrypted frames, which we skip.
    private static func frameData(_ body: Data, flags: UInt16, version: UInt8, unsynchronised: Bool) -> Data? {
        let format = UInt8(truncatingIfNeeded: flags)
        var data = body[...]
        switch version {
        case 3:
            if format & 0xC0 != 0 {
                return nil
            }
            if format & 0x20 != 0 {
                data = data.dropFirst(1) // group ID
            }
        case 4:
            if format & 0x0C != 0 {
                return nil
            }
            if format & 0x40 != 0 {
                data = data.dropFirst(1) // group ID
            }
            if format & 0x01 != 0 {
                data = data.dropFirst(4) // data length indicator
            }
            if format & 0x02 != 0 || unsynchronised {
                return resync(Data(data))
            }
        default: break
        }
        return Data(data)
    }

    private static func handleFrame(_ id: String, _ data: Data, version: UInt8, into frames: inout Frames) throws(ParseError) {
        switch id {
        case "CHAP": try parseChapter(data, version: version, into: &frames)
        case "CTOC": parseTableOfContents(data, into: &frames)
        case "TXXX":
            guard let (encoding, rest) = encoded(data) else { return }
            let (description, value) = splitTerminated(rest, encoding: encoding)
            frames.tags["TXXX:\(decode(description, encoding: encoding))"] = values(value, encoding: encoding)
        case "COMM":
            guard let (encoding, rest) = encoded(data), rest.count >= 3 else { return }
            let (description, text) = splitTerminated(Data(rest.dropFirst(3)), encoding: encoding) // after language
            let key = description.isEmpty ? "COMM" : "COMM:\(decode(description, encoding: encoding))"
            frames.tags[key] = frames.tags[key] ?? values(text, encoding: encoding)
        case "APIC", "PIC": parsePicture(data, isV22: id == "PIC", into: &frames)
        case _ where id.hasPrefix("T") || id == "MVNM" || id == "MVIN":
            guard let (encoding, rest) = encoded(data) else { return }
            frames.tags[id] = values(rest, encoding: encoding)
        default: break
        }
    }

    /// Encoding, format (terminated MIME type, or 3 bytes in v2.2), picture type, description, image.
    private static func parsePicture(_ data: Data, isV22: Bool, into frames: inout Frames) {
        guard let (encoding, rest) = encoded(data) else { return }
        let afterFormat = isV22 ? Data(rest.dropFirst(3)) : splitTerminated(rest, encoding: 0).rest
        guard let pictureType = afterFormat.first else { return }
        let image = splitTerminated(Data(afterFormat.dropFirst()), encoding: encoding).rest
        let isFront = pictureType == 3
        if !image.isEmpty, frames.cover == nil || (isFront && !frames.hasFrontCover) {
            frames.cover = image
            frames.hasFrontCover = isFront
        }
    }

    /// Element ID, start/end ms, start/end byte offsets, then embedded frames (the title is a `TIT2`).
    private static func parseChapter(_ data: Data, version: UInt8, into frames: inout Frames) throws(ParseError) {
        let (elementID, rest) = splitTerminated(data, encoding: 0)
        var reader = ByteReader(rest)
        let startMs: UInt32 = try reader.read()
        try reader.skip(12)
        let embedded = try parseFrames(&reader, version: version, unsynchronised: false)
        let chapter = RawChapter(start: TimeInterval(startMs) / 1000, title: embedded.tags["TIT2"] ?? "")
        frames.chapters.append((elementID.latin1, chapter))
    }

    /// Element ID, flags, child count, child element IDs. Only the top-level table sets chapter order.
    private static func parseTableOfContents(_ data: Data, into frames: inout Frames) {
        let rest = splitTerminated(data, encoding: 0).rest
        guard rest.count >= 2, rest[0] & 0x02 != 0 else { return }
        var remaining = Data(rest.dropFirst(2))
        var children: [String] = []
        for _ in 0 ..< rest[1] where !remaining.isEmpty {
            let (child, after) = splitTerminated(remaining, encoding: 0)
            children.append(child.latin1)
            remaining = after
        }
        frames.tableOfContents = children
    }

    // MARK: - Text

    /// Splits off the leading text-encoding byte.
    private static func encoded(_ data: Data) -> (encoding: UInt8, rest: Data)? {
        data.first.map { ($0, Data(data.dropFirst())) }
    }

    /// Splits at the first terminator: one zero byte, or two at an even offset for UTF-16. No terminator: all text.
    private static func splitTerminated(_ data: Data, encoding: UInt8) -> (text: Data, rest: Data) {
        let wide = encoding == 1 || encoding == 2
        var index = 0
        while index + (wide ? 1 : 0) < data.count {
            if data[index] == 0, !wide || data[index + 1] == 0 {
                return (Data(data[..<index]), Data(data[(index + (wide ? 2 : 1))...]))
            }
            index += wide ? 2 : 1
        }
        return (data, Data())
    }

    /// Decodes a text value; v2.4 separates multiple values with terminators. Nil when empty.
    private static func values(_ data: Data, encoding: UInt8) -> String? {
        // Each UTF-16 value after the first carries its own BOM, which decodes as U+FEFF
        let parts = decode(data, encoding: encoding).split(separator: "\0").map { $0.drop { $0 == "\u{FEFF}" } }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }

    private static func decode(_ data: Data, encoding: UInt8) -> String {
        switch encoding {
        case 0: return data.latin1
        case 1: // UTF-16 with BOM; without one, assume little-endian like most writers
            if data.starts(with: [0xFE, 0xFF]) {
                return utf16(data.dropFirst(2), .utf16BigEndian)
            }
            return utf16(data.starts(with: [0xFF, 0xFE]) ? data.dropFirst(2) : data[...], .utf16LittleEndian)
        case 2: return utf16(data[...], .utf16BigEndian)
        default:
            var reader = ByteReader(data)
            return (try? reader.readUTF8(data.count)) ?? ""
        }
    }

    private static func utf16(_ data: Data.SubSequence, _ encoding: String.Encoding) -> String {
        String(data: Data(data.prefix(data.count & ~1)), encoding: encoding) ?? ""
    }

    /// Undoes unsynchronisation: every `FF 00` becomes `FF`.
    static func resync(_ data: Data) -> Data {
        var output = Data(capacity: data.count)
        var previous: UInt8 = 0
        for byte in data {
            if !(previous == 0xFF && byte == 0) {
                output.append(byte)
            }
            previous = byte
        }
        return output
    }
}

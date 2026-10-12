import Foundation

public struct MP4Metadata: Equatable, Sendable {
    /// From `mvhd`.
    public var duration: TimeInterval?
    /// `ilst` values keyed by atom name (`©nam`, `aART`), or `----:<mean>:<name>` for freeform atoms.
    /// `trkn` and `disk` are `"n"` or `"n/total"`; integer atoms are decimal strings.
    public var tags: [String: String] = [:]
    /// First `covr` image (JPEG or PNG bytes).
    public var cover: Data?
    /// Nero `chpl` chapters. QuickTime chapter tracks need AVFoundation, so `Library` reads those.
    public var chapters: [RawChapter] = []
}

/// Reads metadata, cover and Nero chapters from MP4/M4A/M4B. Pass a memory-mapped `Data`
/// (`.alwaysMapped`): only box headers and `moov` are touched, never the audio in `mdat`.
public enum MP4Parser {
    public static func parse(_ data: Data) throws(ParseError) -> MP4Metadata {
        var file = ByteReader(data)
        var result = MP4Metadata()
        while var box = try file.nextBox() {
            if box.type == "moov" {
                try parseMoov(&box.body, into: &result)
                return result // ignore whatever follows; some taggers leave junk after moov
            }
        }
        throw .malformed("no moov box")
    }

    private static func parseMoov(_ moov: inout ByteReader, into result: inout MP4Metadata) throws(ParseError) {
        while var box = try moov.nextBox() {
            switch box.type {
            case "mvhd": result.duration = try parseMvhd(&box.body)
            case "udta":
                while var child = try box.body.nextBox() {
                    switch child.type {
                    case "chpl": result.chapters = try parseChpl(&child.body)
                    case "meta": try parseMeta(&child.body, into: &result)
                    default: break
                    }
                }
            default: break
            }
        }
    }

    private static func parseMvhd(_ body: inout ByteReader) throws(ParseError) -> TimeInterval? {
        let version: UInt8 = try body.read()
        try body.skip(3 + (version == 1 ? 16 : 8)) // flags, creation and modification times
        let timescale: UInt32 = try body.read()
        let duration: UInt64 = if version == 1 {
            try body.read()
        } else {
            try UInt64(body.read(UInt32.self))
        }
        return timescale == 0 ? nil : TimeInterval(duration) / TimeInterval(timescale)
    }

    /// Nero chapter list: version, flags, (v1) 4 reserved bytes, count, then 100 ns start + Pascal-string title.
    private static func parseChpl(_ body: inout ByteReader) throws(ParseError) -> [RawChapter] {
        let version: UInt8 = try body.read()
        try body.skip(3 + (version == 1 ? 4 : 0))
        let count: UInt8 = try body.read()
        var chapters: [RawChapter] = []
        for _ in 0 ..< count {
            let start: UInt64 = try body.read()
            let titleLength: UInt8 = try body.read()
            let title = try body.readUTF8(Int(titleLength))
            chapters.append(RawChapter(start: TimeInterval(start) / 10_000_000, title: title))
        }
        return chapters
    }

    private static func parseMeta(_ body: inout ByteReader, into result: inout MP4Metadata) throws(ParseError) {
        // iTunes `meta` is a full box (4 bytes of version/flags); QuickTime's isn't, and its first child comes straight away.
        var peek = body
        try peek.skip(4)
        if try peek.readBytes(4) != Data("hdlr".utf8) {
            try body.skip(4)
        }
        while var box = try body.nextBox() {
            while box.type == "ilst", var item = try box.body.nextBox() {
                try parseItem(&item, into: &result)
            }
        }
    }

    private static func parseItem(_ item: inout MP4Box, into result: inout MP4Metadata) throws(ParseError) {
        var key = item.type
        var mean = "", name = ""
        while var child = try item.body.nextBox() {
            switch child.type {
            case "mean", "name":
                try child.body.skip(4) // version and flags
                let text = try child.body.readUTF8(child.body.remaining)
                if child.type == "mean" {
                    mean = text
                } else {
                    name = text
                }
            case "data":
                if item.type == "----" {
                    key = "----:\(mean):\(name)"
                }
                try parseData(&child.body, key: key, into: &result)
                return // first value wins; later `data` boxes are alternates (e.g. extra covers)
            default: break
            }
        }
    }

    private static func parseData(_ body: inout ByteReader, key: String, into result: inout MP4Metadata) throws(ParseError) {
        let typeCode = try body.read(UInt32.self) & 0x00FF_FFFF // high byte is the version
        try body.skip(4) // locale
        let value = try body.readBytes(body.remaining)
        var reader = ByteReader(value)

        if key == "covr" {
            result.cover = value
            return
        }
        let text: String? = switch typeCode {
        case 1: try reader.readUTF8(value.count)
        case 2: String(data: value, encoding: .utf16BigEndian)
        case 0 where key == "trkn" || key == "disk": try trackNumber(&reader)
        case 21 where [1, 2, 4, 8].contains(value.count): try String(signedInteger(&reader, byteCount: value.count))
        default: nil
        }
        if let text = text?.trimmingCharacters(in: CharacterSet(charactersIn: "\0")), !text.isEmpty {
            result.tags[key] = text
        }
    }

    /// `trkn`/`disk`: 2 reserved bytes, number, total.
    private static func trackNumber(_ reader: inout ByteReader) throws(ParseError) -> String {
        try reader.skip(2)
        let number: UInt16 = try reader.read()
        let total: UInt16 = try reader.read()
        return total == 0 ? "\(number)" : "\(number)/\(total)"
    }

    private static func signedInteger(_ reader: inout ByteReader, byteCount: Int) throws(ParseError) -> Int64 {
        switch byteCount {
        case 1: try Int64(reader.read(Int8.self))
        case 2: try Int64(reader.read(Int16.self))
        case 4: try Int64(reader.read(Int32.self))
        default: try reader.read(Int64.self)
        }
    }
}

struct MP4Box {
    /// Four-character code, decoded as Latin-1 so `0xA9` reads as `©`.
    var type: String
    var body: ByteReader
}

extension ByteReader {
    /// The next ISO BMFF box, or nil at the end. Fewer than 8 bytes left also counts as the end,
    /// because QuickTime pads some containers with a 4-byte zero terminator.
    mutating func nextBox() throws(ParseError) -> MP4Box? {
        guard remaining >= 8 else { return nil }
        let size32: UInt32 = try read()
        let type = try readBytes(4).latin1
        let bodyLength: UInt64
        switch size32 {
        case 0: bodyLength = UInt64(remaining) // box runs to the end of its container
        case 1: // 64-bit size follows
            let size: UInt64 = try read()
            guard size >= 16 else { throw .malformed("\(type) box size \(size) is smaller than its header") }
            bodyLength = size - 16
        default:
            guard size32 >= 8 else { throw .malformed("\(type) box size \(size32) is smaller than its header") }
            bodyLength = UInt64(size32 - 8)
        }
        return try MP4Box(type: type, body: slice(Int(clamping: bodyLength)))
    }
}

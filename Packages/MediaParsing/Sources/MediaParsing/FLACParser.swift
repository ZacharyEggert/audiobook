import Foundation

public struct FLACMetadata: Equatable, Sendable {
    /// From `STREAMINFO`; nil when the total sample count is unknown (0).
    public var duration: TimeInterval?
    /// Vorbis comments with upper-cased keys. Repeated keys are joined with `"; "`.
    /// Chapter and picture comments are parsed out and not repeated here.
    public var tags: [String: String] = [:]
    /// Front cover if there is one, else the first picture (`PICTURE` block or `METADATA_BLOCK_PICTURE` comment).
    public var cover: Data?
    /// From `CHAPTERxxx` / `CHAPTERxxxNAME` comments, ordered by number.
    public var chapters: [RawChapter] = []
}

/// Reads FLAC metadata blocks. Skips a leading ID3v2 tag, which some taggers add.
public enum FLACParser {
    public static func parse(_ data: Data) throws(ParseError) -> FLACMetadata {
        var reader = ByteReader(data)
        try reader.skip(ID3Parser.parse(data)?.byteCount ?? 0)
        guard reader.remaining >= 4, try reader.readBytes(4) == Data("fLaC".utf8) else {
            throw .malformed("no fLaC marker")
        }
        var result = FLACMetadata()
        var comments: [(key: String, value: String)] = []
        var hasFrontCover = false
        var isLast = false
        while !isLast {
            let header: UInt8 = try reader.read()
            isLast = header & 0x80 != 0
            var block = try reader.slice(Int(reader.readUInt24()))
            switch header & 0x7F {
            case 0: result.duration = try parseStreamInfo(&block)
            case 4: comments += try parseComments(&block)
            case 6: try addPicture(&block, to: &result, hasFrontCover: &hasFrontCover)
            default: break
            }
        }
        apply(comments, to: &result, hasFrontCover: &hasFrontCover)
        return result
    }

    /// Sorts comments into pictures, chapters and plain tags.
    private static func apply(_ comments: [(key: String, value: String)], to result: inout FLACMetadata, hasFrontCover: inout Bool) {
        var numberedChapters: [Int: (start: TimeInterval?, title: String?)] = [:]
        for (key, value) in comments {
            if key == "METADATA_BLOCK_PICTURE" {
                guard let picture = Data(base64Encoded: value, options: .ignoreUnknownCharacters) else { continue }
                var block = ByteReader(picture)
                try? addPicture(&block, to: &result, hasFrontCover: &hasFrontCover)
            } else if let (number, isName) = chapterKey(key) {
                if isName {
                    numberedChapters[number, default: (nil, nil)].title = value
                } else {
                    numberedChapters[number, default: (nil, nil)].start = clockSeconds(value)
                }
            } else {
                result.tags[key] = result.tags[key].map { "\($0); \(value)" } ?? value
            }
        }
        result.chapters = numberedChapters.sorted { $0.key < $1.key }.compactMap { _, chapter in
            chapter.start.map { RawChapter(start: $0, title: chapter.title ?? "") }
        }
    }

    /// Sample rate is bits 80-99, total samples bits 108-143 (after block sizes, frame sizes).
    private static func parseStreamInfo(_ block: inout ByteReader) throws(ParseError) -> TimeInterval? {
        try block.skip(10)
        let packed: UInt64 = try block.read()
        let sampleRate = packed >> 44
        let totalSamples = packed & 0xF_FFFF_FFFF
        return sampleRate == 0 || totalSamples == 0 ? nil : TimeInterval(totalSamples) / TimeInterval(sampleRate)
    }

    /// Vorbis comment block (little-endian): vendor string, count, then `KEY=value` strings.
    private static func parseComments(_ block: inout ByteReader) throws(ParseError) -> [(key: String, value: String)] {
        try block.skip(Int(block.read(UInt32.self, .little)))
        let count = try block.read(UInt32.self, .little)
        var comments: [(key: String, value: String)] = []
        for _ in 0 ..< count {
            let comment = try block.readUTF8(Int(block.read(UInt32.self, .little)))
            guard let equals = comment.firstIndex(of: "=") else { continue }
            let value = String(comment[comment.index(after: equals)...])
            if !value.isEmpty {
                comments.append((comment[..<equals].uppercased(), value))
            }
        }
        return comments
    }

    /// Picture type, MIME type, description, dimensions and colors, then the image (all big-endian).
    private static func addPicture(_ block: inout ByteReader, to result: inout FLACMetadata, hasFrontCover: inout Bool) throws(ParseError) {
        let pictureType: UInt32 = try block.read()
        try block.skip(Int(block.read(UInt32.self))) // MIME type
        try block.skip(Int(block.read(UInt32.self))) // description
        try block.skip(16) // width, height, depth, colors
        let image = try block.readBytes(Int(block.read(UInt32.self)))
        let isFront = pictureType == 3
        if !image.isEmpty, result.cover == nil || (isFront && !hasFrontCover) {
            result.cover = image
            hasFrontCover = isFront
        }
    }

    /// `CHAPTER012` → (12, false); `CHAPTER012NAME` → (12, true). Other keys → nil.
    private static func chapterKey(_ key: String) -> (number: Int, isName: Bool)? {
        guard key.hasPrefix("CHAPTER") else { return nil }
        var rest = key.dropFirst("CHAPTER".count)
        let isName = rest.hasSuffix("NAME")
        if isName {
            rest = rest.dropLast("NAME".count)
        }
        guard !rest.isEmpty, rest.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(rest) else { return nil }
        return (number, isName)
    }
}

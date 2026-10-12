import Foundation

public enum ParseError: Error, Equatable, Sendable {
    /// A read needed more bytes than the input has left.
    case truncated(offset: Int, needed: Int, available: Int)
    /// The bytes are there but don't make sense for the format.
    case malformed(String)
}

public enum Endian: Sendable {
    case big, little
}

/// Reads binary input front to back. Every read is bounds-checked and throws instead of trapping,
/// so truncated or malicious files fail with `ParseError.truncated`.
public struct ByteReader: Sendable {
    private let data: Data
    /// Bytes consumed so far, from 0.
    public private(set) var offset = 0

    public init(_ data: Data) {
        self.data = data
    }

    public var count: Int {
        data.count
    }

    public var remaining: Int {
        count - offset
    }

    public var isAtEnd: Bool {
        remaining == 0
    }

    public mutating func read<T: FixedWidthInteger>(_: T.Type = T.self, _ endian: Endian = .big) throws(ParseError) -> T {
        try readInteger(byteCount: MemoryLayout<T>.size, endian)
    }

    public mutating func readUInt24(_ endian: Endian = .big) throws(ParseError) -> UInt32 {
        try readInteger(byteCount: 3, endian)
    }

    /// ID3v2 syncsafe integer: 4 bytes, 7 bits each (max 2^28 - 1). Invalid high bits are masked off
    /// rather than rejected; callers that must detect non-syncsafe sizes (older iTunes v2.4 frames) check the raw bytes.
    public mutating func readSyncsafeUInt32() throws(ParseError) -> UInt32 {
        let raw: UInt32 = try read()
        return (raw & 0x7F) | (raw >> 1 & 0x3F80) | (raw >> 2 & 0x1FC000) | (raw >> 3 & 0x0FE0_0000)
    }

    /// Decodes the next `byteCount` bytes as UTF-8. Invalid sequences become U+FFFD instead of failing,
    /// because a slightly broken tag is still worth showing.
    public mutating func readUTF8(_ byteCount: Int) throws(ParseError) -> String {
        // swiftlint:disable:next optional_data_string_conversion
        try String(decoding: data[consume(byteCount)], as: UTF8.self)
    }

    /// Copies the next `byteCount` bytes into a new, zero-indexed `Data`.
    public mutating func readBytes(_ byteCount: Int) throws(ParseError) -> Data {
        try Data(data[consume(byteCount)])
    }

    public mutating func skip(_ byteCount: Int) throws(ParseError) {
        _ = try consume(byteCount)
    }

    /// Consumes the next `byteCount` bytes and returns a reader that can't read past them.
    public mutating func slice(_ byteCount: Int) throws(ParseError) -> ByteReader {
        try ByteReader(data[consume(byteCount)])
    }

    private mutating func readInteger<T: FixedWidthInteger>(byteCount: Int, _ endian: Endian) throws(ParseError) -> T {
        let bytes = try data[consume(byteCount)]
        let ordered = endian == .big ? Array(bytes) : bytes.reversed()
        // Accumulate unsigned so signed types reinterpret the bit pattern instead of trapping
        return T(truncatingIfNeeded: ordered.reduce(UInt64(0)) { $0 << 8 | UInt64($1) })
    }

    /// Range of the next `byteCount` bytes in `data`'s own indices (a `Data` slice doesn't start at 0).
    private mutating func consume(_ byteCount: Int) throws(ParseError) -> Range<Data.Index> {
        guard byteCount >= 0, byteCount <= remaining else {
            throw .truncated(offset: offset, needed: byteCount, available: remaining)
        }
        let start = data.startIndex + offset
        offset += byteCount
        return start ..< start + byteCount
    }
}

import Foundation
@testable import MediaParsing
import Testing

private let sample = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A])

@Test func `reads big and little endian integers`() throws {
    var reader = ByteReader(sample)
    #expect(try reader.read(UInt16.self) == 0x0102)
    #expect(try reader.read(UInt16.self, .little) == 0x0403)
    #expect(try reader.readUInt24() == 0x050607)
    #expect(try reader.readUInt24(.little) == 0x0A0908)
    #expect(reader.isAtEnd)

    var wide = ByteReader(sample)
    #expect(try wide.read(UInt64.self) == 0x0102_0304_0506_0708)
    wide = ByteReader(sample)
    #expect(try wide.read(UInt32.self, .little) == 0x0403_0201)
}

@Test func `reads signed integers by bit pattern`() throws {
    var reader = ByteReader(Data([0xFF, 0xFF, 0xFE, 0x80]))
    #expect(try reader.read(Int16.self) == -1)
    #expect(try reader.read(Int8.self) == -2)
    #expect(try reader.read(Int8.self) == -128)
}

@Test(arguments: [
    ([0x00, 0x00, 0x00, 0x00], 0),
    ([0x00, 0x00, 0x02, 0x01], 257),
    ([0x7F, 0x7F, 0x7F, 0x7F], 0x0FFF_FFFF),
    ([0x00, 0x00, 0x01, 0x7F], 255),
    ([0x80, 0x80, 0x80, 0x81], 1), // high bits masked off
] as [([UInt8], UInt32)])
func `reads syncsafe integers`(bytes: [UInt8], expected: UInt32) throws {
    var reader = ByteReader(Data(bytes))
    #expect(try reader.readSyncsafeUInt32() == expected)
}

@Test func `throws truncated without moving`() throws {
    var reader = ByteReader(sample)
    try reader.skip(8)
    #expect(throws: ParseError.truncated(offset: 8, needed: 4, available: 2)) { try reader.read(UInt32.self) }
    #expect(throws: ParseError.truncated(offset: 8, needed: -1, available: 2)) { try reader.skip(-1) }
    #expect(throws: ParseError.truncated(offset: 8, needed: Int.max, available: 2)) { try reader.readBytes(Int.max) }
    #expect(reader.offset == 8)
    #expect(try reader.read(UInt16.self) == 0x090A)
}

@Test func `slice is bounded and advances the parent`() throws {
    var reader = ByteReader(sample)
    try reader.skip(2)
    var box = try reader.slice(3)
    #expect(reader.offset == 5)
    #expect(box.count == 3)
    #expect(try box.read(UInt16.self) == 0x0304)
    #expect(throws: ParseError.self) { try box.read(UInt16.self) }
    #expect(try box.readBytes(1) == Data([0x05]))

    var nested = try ByteReader(sample).sliced(at: 4, count: 4)
    var inner = try nested.slice(2)
    #expect(try inner.read(UInt16.self) == 0x0506)
    #expect(try nested.read(UInt16.self) == 0x0708)
}

@Test func `readBytes returns zero-indexed data`() throws {
    var reader = try ByteReader(sample).sliced(at: 6, count: 4)
    let bytes = try reader.readBytes(2)
    #expect(bytes.startIndex == 0)
    #expect(bytes[0] == 0x07)
}

/// Fuzz-style: run every read kind against every prefix of the input. Each must either succeed or throw.
@Test func `never traps on truncated input`() {
    let input = Data((0 ..< 64).map { UInt8(truncatingIfNeeded: $0 &* 37) })
    let reads: [(inout ByteReader) throws -> Void] = [
        { _ = try $0.read(UInt8.self) },
        { _ = try $0.read(Int16.self, .little) },
        { _ = try $0.readUInt24() },
        { _ = try $0.read(UInt32.self) },
        { _ = try $0.read(Int64.self, .little) },
        { _ = try $0.readSyncsafeUInt32() },
        { _ = try $0.readBytes(Int($0.remaining / 2 + 1)) },
        { var box = try $0.slice(5); _ = try box.read(UInt64.self) },
        { try $0.skip(3) },
    ]
    for length in 0 ... input.count {
        for first in reads.indices {
            var reader = ByteReader(input.prefix(length))
            var failures = 0
            for step in 0 ..< 40 {
                do { try reads[(first + step) % reads.count](&reader) } catch { failures += 1 }
            }
            #expect(reader.offset <= reader.count)
            #expect(length > 8 || failures > 0)
        }
    }
}

private extension ByteReader {
    /// A reader over `data[start ..< start + count]`, whose indices don't start at 0.
    func sliced(at start: Int, count: Int) throws -> ByteReader {
        var copy = self
        try copy.skip(start)
        return try copy.slice(count)
    }
}

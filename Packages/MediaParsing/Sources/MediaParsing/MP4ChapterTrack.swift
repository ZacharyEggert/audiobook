import Foundation

/// The QuickTime chapter track: a text track that another track names in its `tref/chap` box.
/// Each sample is one chapter, a 2-byte length then the title; its start is the sum of the earlier sample durations.
/// ponytail: ignores the chapter track's edit list (`elst`), which audiobook encoders don't write.
enum MP4ChapterTrack {
    /// Samples past this are ignored, so a corrupt count can't make us loop for ever.
    static let maxChapters = 10000

    /// - Parameters:
    ///   - traks: bodies of every `trak` box in `moov`.
    ///   - file: the whole file, for reading the title samples (only those few bytes of `mdat` are touched).
    static func chapters(in traks: [ByteReader], file: Data) throws(ParseError) -> [RawChapter] {
        var tracksByID: [UInt32: ByteReader] = [:]
        var chapterIDs: [UInt32] = []
        for trak in traks {
            var body = trak
            while var box = try body.nextBox() {
                switch box.type {
                case "tkhd": try tracksByID[trackID(&box.body)] = trak
                case "tref":
                    while var reference = try box.body.nextBox() {
                        while reference.type == "chap", reference.body.remaining >= 4 {
                            try chapterIDs.append(reference.body.read())
                        }
                    }
                default: break
                }
            }
        }
        guard var track = chapterIDs.lazy.compactMap({ tracksByID[$0] }).first else { return [] }
        let tables = try SampleTables(trak: &track)
        let starts = tables.startTimes()
        return zip(starts, tables.sampleOffsets()).map { RawChapter(start: $0, title: title(in: file, at: $1)) }
    }

    private static func trackID(_ tkhd: inout ByteReader) throws(ParseError) -> UInt32 {
        let version: UInt8 = try tkhd.read()
        try tkhd.skip(3 + (version == 1 ? 16 : 8)) // flags, creation and modification times
        return try tkhd.read()
    }

    /// 2-byte length, then UTF-8 or (with a BOM) UTF-16. Unreadable samples, e.g. in a truncated `mdat`, give "".
    private static func title(in file: Data, at offset: UInt64) -> String {
        var reader = ByteReader(file)
        guard let start = Int(exactly: offset), (try? reader.skip(start)) != nil,
              let length = try? reader.read(UInt16.self), let text = try? reader.readBytes(Int(length))
        else { return "" }
        if text.starts(with: [0xFE, 0xFF]) {
            return String(data: text.dropFirst(2), encoding: .utf16BigEndian) ?? ""
        }
        if text.starts(with: [0xFF, 0xFE]) {
            return String(data: text.dropFirst(2), encoding: .utf16LittleEndian) ?? ""
        }
        var textReader = ByteReader(text)
        return (try? textReader.readUTF8(text.count)) ?? ""
    }
}

/// The parts of a track's `mdia` that place its samples in time and in the file.
private struct SampleTables {
    var timescale: UInt32 = 0
    var durations: [(count: UInt32, delta: UInt32)] = [] // stts
    var sizes: [UInt32] = [] // stsz, when samples differ in size
    var uniformSize: UInt32 = 0 // stsz, when they don't
    var sampleCount = 0
    var chunkRuns: [(firstChunk: UInt32, samplesPerChunk: UInt32)] = [] // stsc
    var chunkOffsets: [UInt64] = [] // stco / co64

    init(trak: inout ByteReader) throws(ParseError) {
        while var box = try trak.nextBox() {
            while box.type == "mdia", var child = try box.body.nextBox() {
                if child.type == "mdhd" {
                    let version: UInt8 = try child.body.read()
                    try child.body.skip(3 + (version == 1 ? 16 : 8))
                    timescale = try child.body.read()
                } else if child.type == "minf" {
                    while var stbl = try child.body.nextBox() {
                        while stbl.type == "stbl", var table = try stbl.body.nextBox() {
                            try read(&table)
                        }
                    }
                }
            }
        }
    }

    private mutating func read(_ table: inout MP4Box) throws(ParseError) {
        guard ["stts", "stsz", "stsc", "stco", "co64"].contains(table.type) else { return }
        try table.body.skip(4) // version and flags
        if table.type == "stsz" {
            uniformSize = try table.body.read()
            sampleCount = try min(Int(table.body.read(UInt32.self)), MP4ChapterTrack.maxChapters)
            if uniformSize == 0 {
                for _ in 0 ..< sampleCount {
                    try sizes.append(table.body.read())
                }
            }
            return
        }
        // Every entry is read from the box, so a corrupt count runs out of bytes instead of looping
        let entryCount: UInt32 = try table.body.read()
        for _ in 0 ..< entryCount {
            switch table.type {
            case "stts": try durations.append((table.body.read(), table.body.read()))
            case "stsc":
                try chunkRuns.append((table.body.read(), table.body.read()))
                try table.body.skip(4) // sample description index
            case "stco": try chunkOffsets.append(UInt64(table.body.read(UInt32.self)))
            default: try chunkOffsets.append(table.body.read())
            }
        }
    }

    func startTimes() -> [TimeInterval] {
        guard timescale > 0 else { return [] }
        var starts: [TimeInterval] = []
        var time: UInt64 = 0
        for entry in durations {
            for _ in 0 ..< min(Int(entry.count), sampleCount - starts.count) {
                starts.append(TimeInterval(time) / TimeInterval(timescale))
                time &+= UInt64(entry.delta)
            }
        }
        return starts
    }

    /// Walks the chunks: each holds `samplesPerChunk` samples back to back from its offset.
    func sampleOffsets() -> [UInt64] {
        var offsets: [UInt64] = []
        for (index, chunkOffset) in chunkOffsets.enumerated() where offsets.count < sampleCount {
            let chunk = UInt32(index + 1)
            let perChunk = chunkRuns.last { $0.firstChunk <= chunk }?.samplesPerChunk ?? 0
            var offset = chunkOffset
            for _ in 0 ..< min(Int(perChunk), sampleCount - offsets.count) {
                offsets.append(offset)
                offset &+= UInt64(uniformSize != 0 ? uniformSize : sizes[offsets.count - 1])
            }
        }
        return offsets
    }
}

import Foundation

public struct ProbeResult: Equatable, Sendable {
    public enum Format: String, Sendable {
        case mp4, mp3, flac, aac, wav, aiff, caf
    }

    public enum ChapterSource: Sendable {
        case quickTime, nero, id3, vorbis, cue, overDrive
    }

    public var format: Format
    /// Nil for formats we don't parse a duration from (AAC, WAV, AIFF, CAF); `Library` asks AVFoundation.
    public var duration: TimeInterval?
    /// Book title: album first, then the track title (PLAN §3.3).
    public var title: String?
    /// This file's own title. A multi-file book uses it to name the file's chapter.
    public var trackTitle: String?
    public var author: String?
    public var narrator: String?
    public var series: String?
    public var seriesIndex: Double?
    public var description: String?
    public var year: Int?
    public var genre: String?
    public var publisher: String?
    public var trackNumber: Int?
    public var discNumber: Int?
    public var cover: Data?
    /// File-relative chapters from the first source that has any (PLAN §3.2 steps 1-3). Empty when none does;
    /// one-chapter-per-file and whole-book fallbacks are book-level, in `AudiobookCore`.
    public var chapters: [RawChapter] = []
    public var chapterSource: ChapterSource?
}

/// Reads metadata, cover, duration and chapters from one audio file, whatever its format.
public enum MediaProbe {
    /// - Parameter chapterTrack: the file's QuickTime chapter track, read through AVFoundation by the caller
    ///   (`Library.ChapterTrackReader`), because this package is Foundation-only. Ignored unless the file is MP4.
    public static func probe(_ url: URL, chapterTrack: [RawChapter] = []) throws -> ProbeResult {
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        guard let format = format(of: data) else { throw ParseError.malformed("unrecognised audio format") }
        var raw = try parse(data, format: format, chapterTrack: chapterTrack)
        if raw.chapters.isEmpty, let cue = cueChapters(for: url) {
            raw.chapters = cue
            raw.chapterSource = .cue
        }
        if raw.chapters.isEmpty, let xml = raw.tags["TXXX:OVERDRIVE MEDIAMARKERS"] {
            raw.chapters = OverDriveMarkers.chapters(from: xml)
            raw.chapterSource = raw.chapters.isEmpty ? nil : .overDrive
        }
        return result(format: format, raw: raw)
    }

    /// Detected from the file's signature, not its extension.
    static func format(of data: Data) -> ProbeResult.Format? {
        let head = Data(data.prefix(12))
        func ascii(_ range: Range<Int>) -> String {
            head.count >= range.upperBound ? Data(head[range]).latin1 : ""
        }
        switch (ascii(0 ..< 4), ascii(4 ..< 8), ascii(8 ..< 12)) {
        case ("fLaC", _, _): return .flac
        case (_, "ftyp", _): return .mp4
        case ("RIFF", _, "WAVE"): return .wav
        case ("FORM", _, "AIFF"), ("FORM", _, "AIFC"): return .aiff
        case ("caff", _, _): return .caf
        default: break
        }
        // ID3v2 can precede MP3, AAC (ADTS) or FLAC: look at what follows it
        let audioStart = (try? ID3Parser.parse(data))??.byteCount ?? 0
        if audioStart > 0, audioStart < data.count {
            if data.dropFirst(audioStart).starts(with: Data("fLaC".utf8)) {
                return .flac
            }
            if let next = format(afterTag: data, at: audioStart) {
                return next
            }
            return .mp3 // tagged, so audio; MP3Duration still searches for the first frame
        }
        return format(afterTag: data, at: 0)
    }

    /// MPEG audio frame sync, or ADTS (sync with the reserved layer bits 00).
    private static func format(afterTag data: Data, at offset: Int) -> ProbeResult.Format? {
        if FrameHeader(data, at: offset) != nil {
            return .mp3
        }
        let bytes = data.dropFirst(offset).prefix(2)
        return bytes.count == 2 && bytes.first == 0xFF && bytes.last! & 0xF6 == 0xF0 ? .aac : nil
    }

    // MARK: - Per-format parsing

    /// Tags (upper-cased keys) and chapters from one parser, before mapping.
    private struct Raw {
        var tags: [String: String] = [:]
        var cover: Data?
        var duration: TimeInterval?
        var chapters: [RawChapter] = []
        var chapterSource: ProbeResult.ChapterSource?
        var keys: TagKeys = .id3

        init(tags: [String: String], cover: Data?, duration: TimeInterval?, keys: TagKeys) {
            // Freeform and TXXX names vary in case between taggers ("Narrator", "NARRATOR")
            self.tags = Dictionary(tags.map { ($0.key.uppercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
            self.cover = cover
            self.duration = duration
            self.keys = keys
        }

        mutating func setChapters(_ chapters: [RawChapter], from source: ProbeResult.ChapterSource) {
            guard self.chapters.isEmpty, !chapters.isEmpty else { return }
            self.chapters = chapters
            chapterSource = source
        }
    }

    private static func parse(_ data: Data, format: ProbeResult.Format, chapterTrack: [RawChapter]) throws -> Raw {
        switch format {
        case .mp4:
            let mp4 = try MP4Parser.parse(data)
            var raw = Raw(tags: mp4.tags, cover: mp4.cover, duration: mp4.duration, keys: .mp4)
            raw.setChapters(chapterTrack, from: .quickTime)
            raw.setChapters(mp4.chapters, from: .nero)
            return raw
        case .mp3, .aac:
            let id3 = try ID3Parser.parse(data)
            let duration = format == .mp3 ? try MP3Duration.duration(of: data, audioStart: id3?.byteCount ?? 0) : nil
            var raw = Raw(tags: id3?.tags ?? [:], cover: id3?.cover, duration: duration, keys: .id3)
            raw.setChapters(id3?.chapters ?? [], from: .id3)
            return raw
        case .flac:
            let flac = try FLACParser.parse(data)
            var raw = Raw(tags: flac.tags, cover: flac.cover, duration: flac.duration, keys: .vorbis)
            raw.setChapters(flac.chapters, from: .vorbis)
            return raw
        case .wav, .aiff, .caf:
            return Raw(tags: [:], cover: nil, duration: nil, keys: .id3)
        }
    }

    /// Chapters from `<name>.cue` next to the file: the sheet's entry for this file, or its only entry.
    private static func cueChapters(for url: URL) -> [RawChapter]? {
        guard let data = try? Data(contentsOf: url.deletingPathExtension().appendingPathExtension("cue")) else { return nil }
        let files = CueParser.parse(data).files
        let file = files.first { $0.name.caseInsensitiveCompare(url.lastPathComponent) == .orderedSame }
            ?? (files.count == 1 ? files.first : nil)
        return file.flatMap { $0.chapters.isEmpty ? nil : $0.chapters }
    }

    // MARK: - Metadata mapping (PLAN §3.3)

    /// Upper-cased tag keys to try, in order, for each field.
    private struct TagKeys {
        var title, trackTitle, author, narrator, series, seriesIndex, description, year, genre, publisher, track, disc: [String]

        static let mp4 = TagKeys(
            title: ["©ALB", "©NAM"], trackTitle: ["©NAM"], author: ["AART", "©ART"], narrator: ["©NRT", "©WRT"],
            series: ["©MVN", "----:COM.APPLE.ITUNES:SERIES"], seriesIndex: ["©MVI", "----:COM.APPLE.ITUNES:SERIES-PART"],
            description: ["LDES", "DESC"], // desc is capped at 255 characters, so prefer the long one
            year: ["©DAY"], genre: ["©GEN"], publisher: ["©PUB"], track: ["TRKN"], disc: ["DISK"],
        )
        static let id3 = TagKeys(
            title: ["TALB", "TIT2"], trackTitle: ["TIT2"], author: ["TPE2", "TPE1"], narrator: ["TXXX:NARRATOR", "TCOM"],
            series: ["TXXX:SERIES", "MVNM"], seriesIndex: ["TXXX:SERIES-PART", "MVIN"], description: ["COMM", "TXXX:DESCRIPTION"],
            year: ["TDRC", "TYER"], genre: ["TCON"], publisher: ["TPUB"], track: ["TRCK"], disc: ["TPOS"],
        )
        static let vorbis = TagKeys(
            title: ["ALBUM", "TITLE"], trackTitle: ["TITLE"], author: ["ALBUMARTIST", "ALBUM ARTIST", "ARTIST"],
            narrator: ["NARRATOR", "COMPOSER"], series: ["SERIES"], seriesIndex: ["SERIESPART", "SERIES-PART"],
            description: ["DESCRIPTION"], year: ["DATE", "YEAR"], genre: ["GENRE"], publisher: ["ORGANIZATION", "PUBLISHER"],
            track: ["TRACKNUMBER"], disc: ["DISCNUMBER"],
        )
    }

    private static func result(format: ProbeResult.Format, raw: Raw) -> ProbeResult {
        let keys = raw.keys
        func first(_ candidates: [String]) -> String? {
            candidates.lazy.compactMap { raw.tags[$0]?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
        }
        return ProbeResult(
            format: format, duration: raw.duration,
            title: first(keys.title), trackTitle: first(keys.trackTitle),
            author: first(keys.author), narrator: first(keys.narrator),
            series: first(keys.series), seriesIndex: first(keys.seriesIndex).flatMap { Double($0) },
            description: first(keys.description), year: first(keys.year).flatMap { leadingInt($0, maxDigits: 4) },
            genre: first(keys.genre), publisher: first(keys.publisher),
            trackNumber: first(keys.track).flatMap { leadingInt($0) }, discNumber: first(keys.disc).flatMap { leadingInt($0) },
            cover: raw.cover, chapters: raw.chapters, chapterSource: raw.chapterSource,
        )
    }

    /// `"3/12"` → 3, `"2024-05-01"` → 2024.
    private static func leadingInt(_ text: String, maxDigits: Int = 9) -> Int? {
        Int(text.prefix { $0.isASCII && $0.isNumber }.prefix(maxDigits))
    }
}

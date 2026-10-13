import Foundation

/// An audiobook in global book time (PLAN §3.4). `Library` persists it as `BookRecord`.
public struct Book: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var authors: [String]
    public var narrators: [String]
    public var series: String?
    public var seriesIndex: Double?
    /// Cached cover, relative to the library folder. Nil until the cover pipeline has run.
    public var coverRef: String?
    /// In play order. Each `globalOffset` is the sum of the durations before it.
    public private(set) var files: [AudioFile]
    /// Book-global, sorted, back to back (see `Chapter.normalized`).
    public var chapters: [Chapter]

    public var duration: TimeInterval {
        files.last.map { $0.globalOffset + $0.duration } ?? 0
    }

    public var timeline: BookTimeline {
        BookTimeline(files: files, chapters: chapters)
    }

    /// `files`' offsets are recomputed from their order and durations.
    public init(
        id: UUID = UUID(), title: String, authors: [String] = [], narrators: [String] = [], series: String? = nil,
        seriesIndex: Double? = nil, coverRef: String? = nil, files: [AudioFile], chapters: [Chapter],
    ) {
        self.id = id
        self.title = title
        self.authors = authors
        self.narrators = narrators
        self.series = series
        self.seriesIndex = seriesIndex
        self.coverRef = coverRef
        var offset: TimeInterval = 0
        self.files = files.map { file in
            var file = file
            file.globalOffset = offset
            offset += file.duration
            return file
        }
        self.chapters = chapters
    }
}

public struct AudioFile: Identifiable, Hashable, Sendable {
    public var id: UUID
    /// Relative to the book's folder, with "/" separators.
    public var relativePath: String
    public var duration: TimeInterval
    /// Where this file starts in the book.
    public var globalOffset: TimeInterval
    /// Container format, e.g. "mp3" or "mp4".
    public var format: String

    public init(id: UUID = UUID(), relativePath: String, duration: TimeInterval, globalOffset: TimeInterval = 0, format: String) {
        self.id = id
        self.relativePath = relativePath
        self.duration = duration.isFinite ? max(duration, 0) : 0
        self.globalOffset = globalOffset
        self.format = format
    }
}

/// A chapter in global book seconds.
public struct Chapter: Hashable, Sendable {
    public var index: Int
    public var title: String
    public var start: TimeInterval
    public var end: TimeInterval

    public var duration: TimeInterval {
        end - start
    }

    public init(index: Int, title: String, start: TimeInterval, end: TimeInterval) {
        self.index = index
        self.title = title
        self.start = start
        self.end = end
    }
}

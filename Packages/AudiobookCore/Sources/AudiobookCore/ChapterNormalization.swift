import Foundation

/// One file's contribution to a book's chapters: its own chapters in file-local seconds, or none.
public struct FileChapters: Sendable {
    public var duration: TimeInterval
    /// Names the file's single chapter when it declares none.
    public var title: String
    public var chapters: [(start: TimeInterval, title: String)]

    public init(duration: TimeInterval, title: String, chapters: [(start: TimeInterval, title: String)] = []) {
        self.duration = duration
        self.title = title
        self.chapters = chapters
    }
}

public extension Chapter {
    /// Book-global chapters from each file's own, in play order (PLAN §3.2 steps 4–5):
    /// - a file without chapters becomes one chapter named by its `title`
    /// - starts are offset by the durations of the files before, and a file's first chapter starts with the file
    /// - starts outside their file are dropped; each chapter ends where the next begins, or at the book's end
    /// - zero-length chapters (including repeated starts, where the later one wins) are dropped
    /// - blank titles become "Chapter N"
    static func normalized(_ files: [FileChapters]) -> [Chapter] {
        var marks: [(start: TimeInterval, title: String)] = []
        var offset: TimeInterval = 0
        for file in files {
            let duration = file.duration.isFinite ? max(file.duration, 0) : 0
            let own = file.chapters.filter { $0.start.isFinite && $0.start < duration }.sorted { $0.start < $1.start }
            for (position, mark) in (own.isEmpty ? [(start: 0, title: file.title)] : own).enumerated() {
                marks.append((position == 0 ? offset : offset + max(mark.start, 0), mark.title))
            }
            offset += duration
        }
        var chapters: [Chapter] = []
        for (position, mark) in marks.enumerated() {
            let end = position + 1 < marks.count ? marks[position + 1].start : offset
            guard end > mark.start else { continue }
            let title = mark.title.trimmingCharacters(in: .whitespacesAndNewlines)
            chapters.append(Chapter(
                index: chapters.count, title: title.isEmpty ? "Chapter \(chapters.count + 1)" : title, start: mark.start, end: end,
            ))
        }
        return chapters
    }
}

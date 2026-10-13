import Foundation

/// Maps between global book time, which the UI and storage use, and a position in one file, which the engine plays.
public struct BookTimeline: Sendable {
    public let files: [AudioFile]
    public let chapters: [Chapter]

    /// `files` with their offsets set, as `Book` lays them out.
    public init(files: [AudioFile], chapters: [Chapter]) {
        self.files = files
        self.chapters = chapters
    }

    public var duration: TimeInterval {
        files.last.map { $0.globalOffset + $0.duration } ?? 0
    }

    /// The file playing at `global` (clamped to the book) and the time within it. A file boundary belongs to the
    /// file that starts there; the very end belongs to the last file. Nil for a book without files.
    public func locate(_ global: TimeInterval) -> (fileIndex: Int, local: TimeInterval)? {
        guard !files.isEmpty else { return nil }
        let time = global.isNaN ? 0 : min(max(global, 0), duration)
        // Last file starting at or before `time`; zero-length files hand over to the file after them
        var low = 0, high = files.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if files[mid].globalOffset <= time {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return (low, min(time - files[low].globalOffset, files[low].duration))
    }

    /// Global time of `local` seconds into file `fileIndex`, clamped to that file.
    /// An index past either end gives the book's start or end.
    public func global(fileIndex: Int, local: TimeInterval) -> TimeInterval {
        guard files.indices.contains(fileIndex) else { return fileIndex < 0 ? 0 : duration }
        let file = files[fileIndex]
        return file.globalOffset + min(max(local.isNaN ? 0 : local, 0), file.duration)
    }

    /// The chapter playing at `global`: the last one starting at or before it, or the first before any starts.
    /// ponytail: linear scan, books have tens of chapters. Binary search if a profile says so.
    public func chapter(at global: TimeInterval) -> Chapter? {
        chapters.last { $0.start <= global } ?? chapters.first
    }
}

import Foundation

/// A chapter as a file declares it, in seconds from the start of that file. `AudiobookCore` turns these into book-global chapters.
public struct RawChapter: Equatable, Sendable {
    public var start: TimeInterval
    public var title: String

    public init(start: TimeInterval, title: String) {
        self.start = start
        self.title = title
    }
}

/// `HH:MM:SS.mmm`, also accepting fewer fields (`MM:SS.mmm`, `SS.mmm`). Used by Vorbis and OverDrive chapters.
func clockSeconds(_ text: some StringProtocol) -> TimeInterval? {
    let parts = text.split(separator: ":", omittingEmptySubsequences: false).map { TimeInterval($0) }
    guard (1 ... 3).contains(parts.count), !parts.contains(nil) else { return nil }
    return parts.reduce(0) { $0 * 60 + ($1 ?? 0) }
}

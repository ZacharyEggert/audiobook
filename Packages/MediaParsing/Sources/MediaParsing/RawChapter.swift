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

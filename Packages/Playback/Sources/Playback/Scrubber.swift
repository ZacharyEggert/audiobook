import AudiobookCore
import Foundation

/// What the full player's scrubber spans (PLAN §5 Player).
public enum ScrubberMode: String, CaseIterable, Sendable {
    case chapter, book

    public var toggled: ScrubberMode {
        self == .chapter ? .book : .chapter
    }
}

/// A stretch of book time the scrubber covers. All values are global book seconds, so multi-file books need no special case.
public struct ScrubberSpan: Equatable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval

    public var duration: TimeInterval {
        max(end - start, 0)
    }

    /// Seconds into the span at `global`, clamped to it.
    public func elapsed(at global: TimeInterval) -> TimeInterval {
        min(max(global - start, 0), duration)
    }

    /// Seconds of audio left at `global`.
    public func remaining(at global: TimeInterval) -> TimeInterval {
        duration - elapsed(at: global)
    }

    /// Wall-clock seconds left at `global` when playing at `rate`.
    public func timeLeft(at global: TimeInterval, rate: Float) -> TimeInterval {
        remaining(at: global) / Double(max(rate, PlaybackSpeed.range.lowerBound))
    }
}

public extension PlayerController {
    /// The current chapter for `.chapter`, else the whole book. Without a chapter, `.chapter` spans the book too.
    func scrubberSpan(_ mode: ScrubberMode) -> ScrubberSpan {
        if mode == .chapter, let chapter {
            return ScrubberSpan(start: chapter.start, end: chapter.end)
        }
        return ScrubberSpan(start: 0, end: duration)
    }

    /// Title of the chapter a scrub to `global` would land in, for the scrub preview.
    func chapterTitle(at global: TimeInterval) -> String? {
        book?.timeline.chapter(at: global)?.title
    }
}

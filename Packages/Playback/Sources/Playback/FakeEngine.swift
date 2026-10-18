import AudiobookCore
import Foundation

/// A `PlaybackEngine` on a clock the test moves with `advance(by:)`.
@MainActor public final class FakeEngine: PlaybackEngine {
    public private(set) var book: Book?
    public private(set) var state: PlaybackState = .idle
    public private(set) var currentTime: TimeInterval = 0
    public var rate: Float = 1
    public var volume: Float = 1
    /// Set to make the next `load` throw.
    public var loadError: (any Error)?
    public var onEvent: ((PlaybackEvent) -> Void)?

    public init() {}

    public func load(_ book: Book, folder _: URL, at global: TimeInterval) async throws {
        if let loadError {
            self.loadError = nil
            throw loadError
        }
        self.book = book
        currentTime = clamped(global)
        set(.paused)
        onEvent?(.time(currentTime))
    }

    public func play() {
        guard book != nil, state != .playing else { return }
        if state == .ended {
            currentTime = 0
        }
        set(.playing)
    }

    public func pause() {
        guard state == .playing else { return }
        set(.paused)
    }

    public func seek(to global: TimeInterval) async {
        currentTime = clamped(global)
        if state == .ended {
            set(.paused)
        }
        onEvent?(.time(currentTime))
    }

    /// Moves the clock `seconds` of wall time, scaled by `rate`, if playing. Ends at the book's end.
    public func advance(by seconds: TimeInterval) {
        guard state == .playing, let book else { return }
        currentTime = min(currentTime + seconds * Double(rate), book.duration)
        onEvent?(.time(currentTime))
        if currentTime >= book.duration {
            set(.ended)
        }
    }

    public func fail(_ message: String) {
        set(.paused)
        onEvent?(.failed(message))
    }

    private func set(_ new: PlaybackState) {
        state = new
        onEvent?(.state(new))
    }

    private func clamped(_ global: TimeInterval) -> TimeInterval {
        min(max(global, 0), book?.duration ?? 0)
    }
}

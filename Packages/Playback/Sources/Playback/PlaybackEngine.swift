import AudiobookCore
import Foundation

public enum PlaybackState: Equatable, Sendable {
    case idle, paused, playing
    /// Played to the end of the book.
    case ended
}

/// What an engine reports. Times are global book seconds (PLAN §3.4).
public enum PlaybackEvent: Equatable, Sendable {
    case time(TimeInterval)
    case state(PlaybackState)
    case failed(String)
}

/// Plays one book in global time (PLAN §4). Main actor, like the `PlayerController` that owns it.
/// Chapters are the controller's business: the engine only knows files.
@MainActor public protocol PlaybackEngine: AnyObject {
    /// Loads `book`, whose files are relative to `folder`, paused at `global`.
    func load(_ book: Book, folder: URL, at global: TimeInterval) async throws
    func play()
    func pause()
    func seek(to global: TimeInterval) async
    /// 0.5 … 3.5.
    var rate: Float { get set }
    /// 0 … 1; the sleep timer fades it out.
    var volume: Float { get set }
    var currentTime: TimeInterval { get }
    /// Called on the main actor for every event. Set by the owner; a callback rather than a stream so delivery is
    /// synchronous and tests needn't wait for it.
    var onEvent: ((PlaybackEvent) -> Void)? { get set }
}

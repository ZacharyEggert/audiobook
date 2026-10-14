import AudiobookCore
import Foundation
import Observation

/// The UI's single source of truth for playback (PLAN §4). Owns the engine and turns its events into state.
@MainActor @Observable public final class PlayerController {
    public private(set) var book: Book?
    /// Folder holding `book`'s files.
    public private(set) var folder: URL?
    /// Global book seconds.
    public private(set) var position: TimeInterval = 0
    public private(set) var state: PlaybackState = .idle
    public private(set) var chapter: Chapter?
    public private(set) var lastError: String?
    public var rate: Float = 1 {
        didSet { engine.rate = rate }
    }

    public var skipBackInterval: TimeInterval = 15
    public var skipForwardInterval: TimeInterval = 30

    public var isPlaying: Bool {
        state == .playing
    }

    public var duration: TimeInterval {
        book?.duration ?? 0
    }

    /// Seconds into the current chapter.
    public var chapterElapsed: TimeInterval {
        chapter.map { position - $0.start } ?? position
    }

    @ObservationIgnored public let engine: any PlaybackEngine

    public init(engine: any PlaybackEngine) {
        self.engine = engine
        engine.onEvent = { [weak self] in self?.handle($0) }
    }

    /// Loads `book` paused at `position`.
    public func load(_ book: Book, folder: URL, at position: TimeInterval = 0) async {
        pause()
        lastError = nil
        do {
            try await engine.load(book, folder: folder, at: position)
            engine.rate = rate
            self.book = book
            self.folder = folder
            update(position: engine.currentTime)
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func play() {
        engine.play()
    }

    public func pause() {
        engine.pause()
    }

    public func toggle() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    public func seek(to global: TimeInterval) async {
        guard book != nil else { return }
        await engine.seek(to: min(max(global, 0), duration))
        update(position: engine.currentTime)
    }

    public func skip(by seconds: TimeInterval) async {
        await seek(to: position + seconds)
    }

    public func skipBack() async {
        await skip(by: -skipBackInterval)
    }

    public func skipForward() async {
        await skip(by: skipForwardInterval)
    }

    public func jump(to chapter: Chapter) async {
        await seek(to: chapter.start)
    }

    public func nextChapter() async {
        guard let book, let chapter, let next = book.chapters.first(where: { $0.index > chapter.index }) else { return }
        await jump(to: next)
    }

    /// The chapter's start, or the chapter before when within its first 3 s (like a CD player).
    public func previousChapter() async {
        guard let book, let chapter else { return }
        if position - chapter.start > 3 {
            await jump(to: chapter)
        } else if let previous = book.chapters.last(where: { $0.index < chapter.index }) {
            await jump(to: previous)
        } else {
            await jump(to: chapter)
        }
    }

    private func handle(_ event: PlaybackEvent) {
        switch event {
        case let .time(time): update(position: time)
        case let .state(new): state = new
        case let .failed(message): lastError = message
        }
    }

    private func update(position new: TimeInterval) {
        position = new
        let current = book?.timeline.chapter(at: new)
        if current != chapter {
            chapter = current
        }
    }
}

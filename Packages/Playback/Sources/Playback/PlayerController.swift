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
    /// Set when loading or playing fails; the UI clears it once shown.
    public var lastError: String?
    public var rate: Float = 1 {
        didSet {
            let snapped = PlaybackSpeed.clamp(rate)
            guard snapped == rate else {
                rate = snapped
                return
            }
            engine.rate = rate
            onTimingChange?()
            if !isRestoringRate, let book {
                onRateChange?(book.id, rate)
            }
        }
    }

    /// The speed for books without one of their own.
    public var defaultRate: Float = 1

    public var skipBackInterval: TimeInterval = 15 {
        didSet { onTimingChange?() }
    }

    public var skipForwardInterval: TimeInterval = 30 {
        didSet { onTimingChange?() }
    }

    /// Rewinds a little on resume, more the longer the pause (`SmartRewind`).
    public var smartRewindEnabled = true

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

    /// Asks the app to persist `(bookID, position)`: every 5 s of playback, on pause (including interruptions) and at
    /// the end of the book, and from `saveNow()`.
    @ObservationIgnored public var onPositionSave: ((UUID, TimeInterval) -> Void)?
    /// The book played to its end.
    @ObservationIgnored public var onBookFinished: ((UUID) -> Void)?
    /// Before the engine starts playing: activate the audio session here.
    @ObservationIgnored public var onWillPlay: (() -> Void)?
    /// After anything that breaks extrapolating time from position and rate: load, seek, state, chapter, rate or skip
    /// intervals. Not called on every tick.
    @ObservationIgnored public var onTimingChange: (() -> Void)?

    /// The user changed the speed for this book.
    @ObservationIgnored public var onRateChange: ((UUID, Float) -> Void)?
    /// The speed remembered for a book, if any; `load` uses it instead of `defaultRate`.
    @ObservationIgnored public var savedRate: ((UUID) -> Float?)?

    @ObservationIgnored public private(set) var engine: any PlaybackEngine
    @ObservationIgnored private let makeEngine: () -> any PlaybackEngine
    @ObservationIgnored private var lastSavedPosition: TimeInterval = 0
    /// The user wants playback; survives the engine pausing on its own, so an interruption knows whether to resume.
    @ObservationIgnored private var wantsToPlay = false
    @ObservationIgnored private var resumeAfterInterruption = false
    /// When playback last paused, for smart rewind. Nil after a load, so a relaunch doesn't rewind.
    @ObservationIgnored private var pausedAt: Date?
    @ObservationIgnored private var isRestoringRate = false
    @ObservationIgnored private let now: () -> Date
    /// The rewind-then-play started by `play()`, so tests can wait for it.
    @ObservationIgnored private(set) var resumeTask: Task<Void, Never>?

    /// `makeEngine` is called now and again after a media services reset.
    public init(makeEngine: @escaping () -> any PlaybackEngine, now: @escaping () -> Date = Date.init) {
        self.makeEngine = makeEngine
        self.now = now
        engine = makeEngine()
        engine.onEvent = { [weak self] in self?.handle($0) }
    }

    /// A media services reset reloads into the same `engine`.
    public convenience init(engine: any PlaybackEngine, now: @escaping () -> Date = Date.init) {
        self.init(makeEngine: { engine }, now: now)
    }

    /// Loads `book` paused at `position`.
    public func load(_ book: Book, folder: URL, at position: TimeInterval = 0) async {
        pause()
        lastError = nil
        do {
            try await engine.load(book, folder: folder, at: position)
            pausedAt = nil
            if book.id != self.book?.id {
                isRestoringRate = true
                rate = savedRate?(book.id) ?? defaultRate
                isRestoringRate = false
            }
            engine.rate = rate // didSet skips an unchanged rate, e.g. on a rebuilt engine
            self.book = book
            self.folder = folder
            update(position: engine.currentTime)
            lastSavedPosition = self.position
            onTimingChange?()
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func play() {
        guard book != nil else { return }
        wantsToPlay = true
        onWillPlay?()
        let rewind = smartRewindEnabled && state != .playing ? pausedAt
            .map { SmartRewind.seconds(afterPause: now().timeIntervalSince($0)) } ?? 0 : 0
        pausedAt = nil
        guard rewind > 0 else {
            engine.play()
            return
        }
        resumeTask = Task {
            await seek(to: position - rewind)
            if wantsToPlay {
                engine.play()
            }
        }
    }

    public func pause() {
        if state == .playing {
            pausedAt = now()
        }
        wantsToPlay = false
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
        onTimingChange?()
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

    /// Fires `onPositionSave` now, e.g. when the app goes to the background.
    public func saveNow() {
        guard let book else { return }
        lastSavedPosition = position
        onPositionSave?(book.id, position)
    }

    /// Reacts to the audio session (PLAN §4): pause on interruption and resume after it if we were playing, pause when
    /// headphones go away, rebuild the engine when media services reset.
    public func handle(_ event: AudioSessionEvent) async {
        switch event {
        case .interruptionBegan:
            resumeAfterInterruption = wantsToPlay
            pause()
        case let .interruptionEnded(shouldResume):
            if shouldResume, resumeAfterInterruption {
                play()
            }
            resumeAfterInterruption = false
        case .oldDeviceUnavailable:
            pause()
        case .mediaServicesReset:
            await rebuildEngine()
        }
    }

    /// A fresh engine with the book reloaded, paused where it was.
    private func rebuildEngine() async {
        engine.onEvent = nil
        engine = makeEngine()
        engine.onEvent = { [weak self] in self?.handle($0) }
        wantsToPlay = false
        state = .idle
        if let book, let folder {
            await load(book, folder: folder, at: position)
        }
    }

    private func handle(_ event: PlaybackEvent) {
        switch event {
        case let .time(time):
            update(position: time)
            // ponytail: 5 s of book time, so more often in wall time at speed; harmless
            if state == .playing, abs(position - lastSavedPosition) >= 5 {
                saveNow()
            }
        case let .state(new):
            let old = state
            state = new
            if new == .ended {
                wantsToPlay = false
                saveNow()
                if let book {
                    onBookFinished?(book.id)
                }
            } else if old == .playing, new == .paused {
                saveNow()
            }
            if new != old {
                onTimingChange?()
            }
        case let .failed(message):
            lastError = message
            wantsToPlay = false
        }
    }

    private func update(position new: TimeInterval) {
        position = new
        let current = book?.timeline.chapter(at: new)
        if current != chapter {
            chapter = current
            onTimingChange?()
        }
    }
}

/// What the audio session reports, reduced to what playback reacts to. `AudioSession` maps `AVAudioSession`'s
/// notifications to these on iOS.
public enum AudioSessionEvent: Equatable, Sendable {
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    /// Headphones unplugged or Bluetooth gone.
    case oldDeviceUnavailable
    case mediaServicesReset
}

/// How far to back up when resuming (PLAN §4): 0 s after under a minute, 5 s under 10 minutes, 15 s under an hour,
/// else 30 s.
public enum SmartRewind {
    public static func seconds(afterPause pause: TimeInterval) -> TimeInterval {
        switch pause {
        case ..<60: 0
        case ..<600: 5
        case ..<3600: 15
        default: 30
        }
    }
}

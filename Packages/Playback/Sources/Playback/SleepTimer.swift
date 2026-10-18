import Foundation
import Observation

/// Stops playback after a while (PLAN §5): off → running → fading → stopped. Counts down only while playing, in wall
/// time. The owner calls `tick` on every playback time event and `playbackStarted()` / `playbackPaused()`; it reports
/// back through `onVolume` (fade) and `onStop`. The clock is injected, so tests move it by hand.
@MainActor @Observable public final class SleepTimer {
    public enum Mode: Equatable, Sendable {
        case duration(TimeInterval)
        /// Stops at this global book time.
        case endOfChapter(end: TimeInterval)
    }

    public enum State: Equatable, Sendable {
        case off, running(Mode), fading(Mode), stopped
    }

    /// The fade starts this many seconds before the stop.
    public static let fadeDuration: TimeInterval = 10
    /// What `extend()` adds when no duration has been used yet.
    public static let defaultExtension: TimeInterval = 15 * 60

    public private(set) var state: State = .off
    /// Wall seconds until the stop; nil when off or stopped.
    public private(set) var remaining: TimeInterval?
    /// The last duration started, which a shake extends by.
    public private(set) var lastDuration: TimeInterval?

    /// Pause playback.
    @ObservationIgnored public var onStop: (() -> Void)?
    /// Output volume, 0 … 1.
    @ObservationIgnored public var onVolume: ((Float) -> Void)?

    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var lastTick: Date?
    @ObservationIgnored private var isFaded = false

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    public var isActive: Bool {
        switch state {
        case .running, .fading: true
        case .off, .stopped: false
        }
    }

    /// Starts (or restarts) the timer. `position` and `rate` only matter for end-of-chapter.
    public func start(_ mode: Mode, position: TimeInterval = 0, rate: Float = 1) {
        switch mode {
        case let .duration(seconds):
            lastDuration = seconds
            remaining = seconds
        case let .endOfChapter(end):
            remaining = Self.chapterLeft(end, position: position, rate: rate)
        }
        state = .running(mode)
        lastTick = now()
        setVolume(1)
        evaluate()
    }

    /// Adds `lastDuration` (or 15 min) to a running timer and restores the volume. End-of-chapter becomes a plain
    /// duration. A stopped or off timer is left alone.
    public func extend(position: TimeInterval = 0, rate: Float = 1) {
        let seconds = lastDuration ?? Self.defaultExtension
        switch state {
        case let .running(.duration(length)), let .fading(.duration(length)):
            remaining = (remaining ?? 0) + seconds
            state = .running(.duration(length))
            evaluate()
        case .running(.endOfChapter), .fading(.endOfChapter):
            start(.duration(seconds), position: position, rate: rate)
        case .off, .stopped:
            break
        }
    }

    public func cancel() {
        state = .off
        remaining = nil
        lastTick = nil
        setVolume(1)
    }

    public func playbackStarted() {
        lastTick = now()
    }

    public func playbackPaused() {
        lastTick = nil
    }

    /// Advances the countdown by the wall time since the last tick.
    public func tick(position: TimeInterval, rate: Float) {
        guard isActive else { return }
        let current = now()
        defer { lastTick = current }
        guard let lastTick else { return }
        switch state {
        case .running(.duration), .fading(.duration):
            remaining = (remaining ?? 0) - current.timeIntervalSince(lastTick)
        case let .running(.endOfChapter(end)), let .fading(.endOfChapter(end)):
            remaining = Self.chapterLeft(end, position: position, rate: rate)
        case .off, .stopped:
            return
        }
        evaluate()
    }

    /// Moves between running, fading and stopped for the current `remaining`.
    private func evaluate() {
        let mode: Mode
        switch state {
        case let .running(current), let .fading(current): mode = current
        case .off, .stopped: return
        }
        guard let left = remaining else { return }
        apply(mode, left)
    }

    private func apply(_ mode: Mode, _ left: TimeInterval) {
        if left <= 0 {
            state = .stopped
            remaining = nil
            onStop?()
            setVolume(1)
        } else if left <= Self.fadeDuration {
            state = .fading(mode)
            setVolume(Float(left / Self.fadeDuration))
        } else {
            state = .running(mode)
            setVolume(1)
        }
    }

    private func setVolume(_ volume: Float) {
        guard volume != 1 || isFaded else { return }
        isFaded = volume != 1
        onVolume?(volume)
    }

    private static func chapterLeft(_ end: TimeInterval, position: TimeInterval, rate: Float) -> TimeInterval {
        (end - position) / Double(max(rate, 0.1))
    }
}

/// An automatic sleep timer for listening at night: starting playback between `startHour` and `endHour` (which may
/// wrap past midnight) starts a timer of `minutes`.
public struct NightTimer: Equatable, Sendable {
    public var startHour: Int
    public var endHour: Int
    public var minutes: Int

    public init(startHour: Int = 22, endHour: Int = 6, minutes: Int = 30) {
        self.startHour = startHour
        self.endHour = endHour
        self.minutes = minutes
    }

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return startHour <= endHour ? (startHour ..< endHour).contains(hour) : hour >= startHour || hour < endHour
    }
}

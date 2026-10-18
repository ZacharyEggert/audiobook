import Foundation
import Playback

/// Playback settings kept in `UserDefaults`; `SettingsScreen` edits them through `@AppStorage` with these keys.
enum PlayerSettings {
    static let skipBackKey = "skipBackInterval"
    static let skipForwardKey = "skipForwardInterval"
    static let smartRewindKey = "smartRewind"
    static let defaultSpeedKey = "defaultSpeed"
    static let bookmarkOnPreviousKey = "bookmarkOnPreviousTrack"
    static let nightTimerKey = "nightTimer"
    static let nightStartKey = "nightTimerStartHour"
    static let nightEndKey = "nightTimerEndHour"
    static let nightMinutesKey = "nightTimerMinutes"
    private static let bookSpeedPrefix = "bookSpeed."
    static let intervals: [Int] = [5, 10, 15, 30, 45, 60, 90]

    @MainActor static func apply(to player: PlayerController, defaults: UserDefaults = .standard) {
        player.skipBackInterval = interval(skipBackKey, default: 15, defaults)
        player.skipForwardInterval = interval(skipForwardKey, default: 30, defaults)
        let speed = defaults.double(forKey: defaultSpeedKey)
        player.defaultRate = speed > 0 ? PlaybackSpeed.clamp(Float(speed)) : 1
        player.smartRewindEnabled = defaults.object(forKey: smartRewindKey) as? Bool ?? true
        player.previousTrackAddsBookmark = defaults.bool(forKey: bookmarkOnPreviousKey)
        player.nightTimer = defaults.bool(forKey: nightTimerKey) ? NightTimer(
            startHour: defaults.object(forKey: nightStartKey) as? Int ?? 22,
            endHour: defaults.object(forKey: nightEndKey) as? Int ?? 6,
            minutes: defaults.object(forKey: nightMinutesKey) as? Int ?? 30,
        ) : nil
    }

    // ponytail: per-book speed in UserDefaults doesn't sync; move onto ProgressRecord (schema V2) when M6 syncs the library
    /// Speed remembered for one book.
    static func speed(for bookID: UUID, defaults: UserDefaults = .standard) -> Float? {
        let speed = defaults.double(forKey: bookSpeedPrefix + bookID.uuidString)
        return speed > 0 ? Float(speed) : nil
    }

    static func setSpeed(_ speed: Float, for bookID: UUID, defaults: UserDefaults = .standard) {
        defaults.set(speed, forKey: bookSpeedPrefix + bookID.uuidString)
    }

    private static func interval(_ key: String, default fallback: Int, _ defaults: UserDefaults) -> TimeInterval {
        let value = defaults.integer(forKey: key)
        return TimeInterval(intervals.contains(value) ? value : fallback)
    }
}

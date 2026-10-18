import Foundation
import Playback

/// Playback settings kept in `UserDefaults`; `SettingsScreen` edits them through `@AppStorage` with these keys.
enum PlayerSettings {
    static let skipBackKey = "skipBackInterval"
    static let skipForwardKey = "skipForwardInterval"
    static let smartRewindKey = "smartRewind"
    static let intervals: [Int] = [5, 10, 15, 30, 45, 60, 90]

    @MainActor static func apply(to player: PlayerController, defaults: UserDefaults = .standard) {
        player.skipBackInterval = interval(skipBackKey, default: 15, defaults)
        player.skipForwardInterval = interval(skipForwardKey, default: 30, defaults)
        player.smartRewindEnabled = defaults.object(forKey: smartRewindKey) as? Bool ?? true
    }

    private static func interval(_ key: String, default fallback: Int, _ defaults: UserDefaults) -> TimeInterval {
        let value = defaults.integer(forKey: key)
        return TimeInterval(intervals.contains(value) ? value : fallback)
    }
}

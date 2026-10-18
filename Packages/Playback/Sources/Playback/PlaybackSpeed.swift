/// Playback speeds (PLAN §4): 0.5× to 3.5× in 0.05 steps.
public enum PlaybackSpeed {
    public static let range: ClosedRange<Float> = 0.5 ... 3.5
    public static let step: Float = 0.05
    public static let presets: [Float] = [1, 1.25, 1.5, 1.75, 2]
    /// What the lock screen offers: the presets plus the slower and faster speeds the old menu had.
    public static let remoteRates: [Float] = [0.5, 0.75] + presets + [2.5, 3, 3.5]

    /// `rate` kept in `range` and snapped to the nearest step, so a stepper's float drift never shows.
    public static func clamp(_ rate: Float) -> Float {
        // divides by 20 rather than multiplying by `step`, which would leave float drift (21 × 0.05 ≠ 1.05)
        (min(max(rate, range.lowerBound), range.upperBound) * 20).rounded() / 20
    }
}

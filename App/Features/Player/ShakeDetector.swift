import CoreMotion
import Foundation

/// Calls `onShake` when the phone is shaken, for as long as it's started (the sleep timer runs it only while active).
@MainActor final class ShakeDetector {
    /// Acceleration beyond gravity, in g, that counts as a shake.
    static let threshold = 1.8
    private static let cooldown: TimeInterval = 2

    var onShake: (() -> Void)?
    private let motion = CMMotionManager()
    private var lastShake = Date.distantPast

    static func isShake(_ a: CMAcceleration) -> Bool {
        (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot() > threshold
    }

    func start() {
        guard motion.isAccelerometerAvailable, !motion.isAccelerometerActive else { return }
        motion.accelerometerUpdateInterval = 0.1
        motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data, Self.isShake(data.acceleration), Date().timeIntervalSince(lastShake) > Self.cooldown
            else { return }
            lastShake = Date()
            onShake?()
        }
    }

    func stop() {
        motion.stopAccelerometerUpdates()
    }
}

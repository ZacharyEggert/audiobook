import AVFoundation
import MediaParsing

/// `MediaProbe`, plus AVFoundation durations for the formats `MediaParsing` doesn't measure (AAC, WAV, AIFF, CAF).
public enum AudioProbe {
    public static func probe(_ url: URL) async throws -> ProbeResult {
        var result = try MediaProbe.probe(url)
        if result.duration == nil {
            let duration = try await AVURLAsset(url: url).load(.duration)
            result.duration = duration.isNumeric ? duration.seconds : nil
        }
        return result
    }
}

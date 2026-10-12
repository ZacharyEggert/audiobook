import AVFoundation
import MediaParsing

/// `MediaProbe` plus the parts that need AVFoundation: QuickTime chapter tracks (first in the chapter
/// resolution order, PLAN §3.2) and durations for formats `MediaParsing` doesn't measure.
public enum AudioProbe {
    public static func probe(_ url: URL) async throws -> ProbeResult {
        var result = try MediaProbe.probe(url)
        if result.format == .mp4 {
            // ponytail: probes twice when there's a chapter track; moov parsing is cheap next to AVFoundation's load
            let chapterTrack = try await ChapterTrackReader.chapters(of: url)
            if !chapterTrack.isEmpty {
                result = try MediaProbe.probe(url, chapterTrack: chapterTrack)
            }
        }
        if result.duration == nil {
            let duration = try await AVURLAsset(url: url).load(.duration)
            result.duration = duration.isNumeric ? duration.seconds : nil
        }
        return result
    }
}

import AVFoundation
import MediaParsing

/// Reads the QuickTime chapter track of an MP4/M4B. AVFoundation ignores Nero `chpl` chapters,
/// so `MP4Parser` covers those.
public enum ChapterTrackReader {
    public static func chapters(of url: URL) async throws -> [RawChapter] {
        let asset = AVURLAsset(url: url)
        var groups = try await asset.loadChapterMetadataGroups(bestMatchingPreferredLanguages: Locale.preferredLanguages)
        // No chapter locale matches the user's languages: fall back to whatever the file has
        if groups.isEmpty, let locale = try await asset.load(.availableChapterLocales).first {
            groups = try await asset.loadChapterMetadataGroups(withTitleLocale: locale, containingItemsWithCommonKeys: [])
        }
        var chapters: [RawChapter] = []
        for group in groups {
            let titleItem = AVMetadataItem.metadataItems(from: group.items, filteredByIdentifier: .commonIdentifierTitle).first
            let title = try await titleItem?.load(.stringValue) ?? ""
            chapters.append(RawChapter(start: group.timeRange.start.seconds, title: title))
        }
        return chapters
    }
}

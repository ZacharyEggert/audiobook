import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Book covers: picked at import, then downscaled on demand into a per-device cache (PLAN §3.3).
///
/// The full cover lives in the book's folder, so it syncs with the audio. The sized copies live in Caches, keyed by
/// book ID, and are rebuilt whenever the cover is newer than them.
public struct CoverStore: Sendable {
    /// Longest side in pixels: 3× the points each place shows.
    public enum Size: Int, Sendable, CaseIterable {
        case list = 180, grid = 480, player = 1080
    }

    public let libraryRoot: URL
    public let cacheRoot: URL

    public static var defaultCacheRoot: URL {
        .cachesDirectory.appending(path: "Covers", directoryHint: .isDirectory)
    }

    public init(libraryRoot: URL = LibraryImporter.defaultRoot, cacheRoot: URL = CoverStore.defaultCacheRoot) {
        self.libraryRoot = libraryRoot
        self.cacheRoot = cacheRoot
    }

    /// The cover at `size`, making it first if the cache is missing or stale. Nil when the book has no readable cover.
    /// - Parameter coverRef: `BookRecord.coverRef`, relative to the library folder.
    @concurrent public func thumbnail(bookID: UUID, coverRef: String, size: Size) async -> URL? {
        let source = libraryRoot.appending(path: coverRef)
        let cached = cacheRoot.appending(path: "\(bookID.uuidString)/\(size).jpg")
        if let cachedDate = Self.modified(cached), let sourceDate = Self.modified(source), cachedDate >= sourceDate {
            return cached
        }
        guard let image = CGImageSourceCreateWithURL(source as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(image, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: size.rawValue,
              ] as CFDictionary)
        else { return nil }

        try? FileManager.default.createDirectory(at: cached.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(cached as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? cached : nil
    }

    /// Drops a book's sized covers, e.g. when the book is deleted.
    public func removeCache(for bookID: UUID) {
        try? FileManager.default.removeItem(at: cacheRoot.appending(path: bookID.uuidString))
    }

    private static func modified(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    // MARK: - Picking at import

    /// The book's cover, relative to its `folder`: the embedded picture (written out), else `cover.jpg|png`,
    /// `folder.jpg`, then the largest image (PLAN §3.3). Shallower images win name ties.
    /// - Parameter images: Images already in `folder`, relative to it.
    static func saveCover(embedded: Data?, images: [String], in folder: URL) -> String? {
        if let embedded, CGImageSourceCreateWithData(embedded as CFData, nil).flatMap(CGImageSourceGetType) != nil {
            let name = embedded.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "embedded-cover.png" : "embedded-cover.jpg"
            if (try? embedded.write(to: folder.appending(path: name))) != nil {
                return name
            }
        }
        let byDepth = images.sorted { $0.split(separator: "/").count < $1.split(separator: "/").count }
        for name in ["cover.jpg", "cover.jpeg", "cover.png", "folder.jpg"] {
            if let match = byDepth.first(where: { ($0 as NSString).lastPathComponent.lowercased() == name }) {
                return match
            }
        }
        func size(_ image: String) -> Int {
            (try? folder.appending(path: image).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return images.max { size($0) < size($1) }
    }
}

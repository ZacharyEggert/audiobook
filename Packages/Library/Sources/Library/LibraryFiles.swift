import Foundation
import SwiftData

/// What each book takes on disk, and removing it (PLAN §5, §11 storage).
public struct LibraryFiles: Sendable {
    public let root: URL

    public init(root: URL = LibraryImporter.defaultRoot) {
        self.root = root
    }

    public func folder(for bookID: UUID) -> URL {
        root.appending(path: bookID.uuidString, directoryHint: .isDirectory)
    }

    /// Bytes on disk under each book's folder.
    @concurrent public func usage(of bookIDs: [UUID]) async -> [UUID: Int64] {
        Dictionary(uniqueKeysWithValues: bookIDs.map { ($0, Self.allocatedSize(of: folder(for: $0))) })
    }

    /// Whether every audio file is on this device.
    /// - Parameter audioPaths: `FileRecord.relativePath`s.
    public func isDownloaded(bookID: UUID, audioPaths: [String]) -> Bool {
        !audioPaths.isEmpty && audioPaths
            .allSatisfy { FileManager.default.fileExists(atPath: folder(for: bookID).appending(path: $0).path) }
    }

    /// Deletes the book's audio but keeps its record, cover, progress and bookmarks.
    /// ponytail: audio is local only until M6 (#76), so this can't be undone yet; then it evicts the iCloud copy instead.
    public func removeDownload(bookID: UUID, audioPaths: [String]) throws {
        for path in audioPaths {
            let url = folder(for: bookID).appending(path: path)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    static func allocatedSize(of folder: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: Array(keys))
        var total: Int64 = 0
        while let file = files?.nextObject() as? URL {
            let values = try? file.resourceValues(forKeys: keys)
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        return total
    }
}

public extension ModelContext {
    /// Deletes a book everywhere: its record, progress, bookmarks, place in collections, then its folder.
    func deleteBook(_ book: BookRecord, files: LibraryFiles) throws {
        let id = book.id
        try delete(model: ProgressRecord.self, where: #Predicate { $0.bookID == id })
        try delete(model: BookmarkRecord.self, where: #Predicate { $0.bookID == id })
        for collection in try fetch(FetchDescriptor<CollectionRecord>()) where collection.bookIDs.contains(id) {
            collection.bookIDs.removeAll { $0 == id }
        }
        delete(book)
        try save()
        try? FileManager.default.removeItem(at: files.folder(for: id))
    }
}

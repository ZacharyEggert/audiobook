import Foundation
import ZIPFoundation

/// Unpacks a zip so the importer can treat it like a picked folder (PLAN §3.1).
enum ZipExtraction {
    enum Failure: Error, LocalizedError {
        /// An entry would land outside the folder it's extracted to (`../`, or an absolute path).
        case unsafeEntry(String)

        var errorDescription: String? {
            switch self {
            case .unsafeEntry: "This archive has files that would land outside it, so it wasn't opened."
            }
        }
    }

    /// Bytes the archive's files take once extracted.
    static func extractedSize(of zip: URL) throws -> Int64 {
        try Archive(url: zip, accessMode: .read).reduce(Int64(0)) { $0 + Int64(clamping: $1.uncompressedSize) }
    }

    /// Extracts `zip` into a new folder named after it inside `directory`, skipping `__MACOSX` and symlinks.
    /// Checks every entry before writing any.
    /// - Returns: The one folder or file at the top of the archive, or the new folder when there are several.
    static func extract(_ zip: URL, into directory: URL) throws -> URL {
        let archive = try Archive(url: zip, accessMode: .read)
        let folder = directory.appending(path: zip.deletingPathExtension().lastPathComponent, directoryHint: .isDirectory)
        let base = folder.standardizedFileURL.path + "/"
        let entries = try archive.filter { entry in
            guard entry.type != .symlink, entry.path.split(separator: "/").first != "__MACOSX" else { return false }
            guard folder.appending(path: entry.path).standardizedFileURL.path.hasPrefix(base) else {
                throw Failure.unsafeEntry(entry.path)
            }
            return true
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for entry in entries {
            try Task.checkCancellation()
            _ = try archive.extract(entry, to: folder.appending(path: entry.path))
        }
        let fileManager = FileManager.default
        let top = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        return top.count == 1 ? top[0] : folder
    }
}

extension LibraryImporter {
    /// `items` with each zip swapped for what it extracts to. A zip that can't be opened, or is unsafe, is reported.
    func unzip(_ items: [URL], into directory: URL, failures: inout [ImportFailure]) throws -> [URL] {
        let zips = items.filter { $0.pathExtension.lowercased() == "zip" && !$0.hasDirectoryPath }
        guard !zips.isEmpty else { return items }
        let needed = zips.reduce(Int64(0)) { $0 + ((try? ZipExtraction.extractedSize(of: $1)) ?? 0) }
        let available = try availableCapacity(root)
        guard needed <= available else { throw ImportError.insufficientSpace(needed: needed, available: available) }

        return try items.compactMap { item in
            guard zips.contains(item) else { return item }
            do {
                return try ZipExtraction.extract(item, into: directory.appending(path: UUID().uuidString))
            } catch is CancellationError {
                throw CancellationError()
            } catch let failure as ZipExtraction.Failure {
                failures.append(ImportFailure(path: item.lastPathComponent, reason: failure.localizedDescription))
            } catch {
                failures.append(ImportFailure(path: item.lastPathComponent, reason: "The archive is damaged or isn't a zip file."))
            }
            return nil
        }
    }
}

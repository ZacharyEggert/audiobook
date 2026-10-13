import AudiobookCore
import Foundation
import MediaParsing
import SwiftData

public struct ImportProgress: Equatable, Sendable {
    public enum Phase: Sendable {
        case copying, reading, saving
    }

    public var phase: Phase
    /// Files for copying and reading, books for saving.
    public var completed: Int
    public var total: Int
}

/// A file that didn't make it into the library, and why. Never fatal to the rest of the import.
public struct ImportFailure: Equatable, Sendable {
    /// Under the picked item's name, e.g. `"Dune/CD3/04.mp3"`.
    public var path: String
    public var reason: String
}

public struct ImportSummary: Equatable, Sendable {
    public var bookIDs: [UUID] = []
    public var failures: [ImportFailure] = []
}

public enum ImportEvent: Equatable, Sendable {
    case progress(ImportProgress)
    case finished(ImportSummary)
}

public enum ImportError: Error, Equatable, LocalizedError {
    case insufficientSpace(needed: Int64, available: Int64)

    public var errorDescription: String? {
        switch self {
        case let .insufficientSpace(needed, available):
            let format = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
            return "This import needs \(format(needed)), but only \(format(available)) is free."
        }
    }
}

/// Copies picked files and folders into the library, reads them, groups them into books and saves those (PLAN §5).
///
/// Every file is copied into a staging folder first, so security-scoped access is held only while copying.
/// Each book's files then move into `<root>/<bookID>/`. Cancelling or failing removes the staging folder and the
/// folders of books not yet saved; books saved in earlier batches stay.
public actor LibraryImporter: ModelActor {
    public nonisolated let modelContainer: ModelContainer
    public nonisolated let modelExecutor: any ModelExecutor
    /// Holds one folder per book, named by its ID.
    public nonisolated let root: URL
    let availableCapacity: @Sendable (URL) throws -> Int64

    static let audioExtensions: Set = ["m4b", "m4a", "mp4", "aac", "mp3", "flac", "wav", "aif", "aiff", "aifc", "caf"]
    static let imageExtensions: Set = ["jpg", "jpeg", "png"]
    private static let batchSize = 20

    /// ponytail: local until M6, which moves the library into the iCloud Drive container so audio syncs with the store.
    public static var defaultRoot: URL {
        .applicationSupportDirectory.appending(path: "Library", directoryHint: .isDirectory)
    }

    /// - Parameter availableCapacity: Free bytes on `root`'s volume. Replaceable for tests.
    public init(
        modelContainer: ModelContainer, root: URL = LibraryImporter.defaultRoot,
        availableCapacity: @escaping @Sendable (URL) throws -> Int64 = LibraryImporter.volumeCapacity,
    ) {
        self.modelContainer = modelContainer
        modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(modelContainer))
        self.root = root
        self.availableCapacity = availableCapacity
    }

    public static func volumeCapacity(_ url: URL) throws -> Int64 {
        try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? .max
    }

    public nonisolated func folder(for bookID: UUID) -> URL {
        root.appending(path: bookID.uuidString, directoryHint: .isDirectory)
    }

    /// `importItems` as a stream of progress, then the summary. Ending the stream early cancels the import.
    public nonisolated func importEvents(_ items: [URL], removingSources: Bool = false) -> AsyncThrowingStream<ImportEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let summary = try await importItems(items, removingSources: removingSources) { continuation.yield(.progress($0)) }
                    continuation.yield(.finished(summary))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Imports files and folders, which may be security-scoped.
    /// - Parameter removingSources: Delete `items` afterwards, as for files dropped into Documents.
    /// - Throws: `ImportError.insufficientSpace` before copying anything, `CancellationError`, or a store error.
    public func importItems(
        _ items: [URL], removingSources: Bool = false, progress: @Sendable (ImportProgress) -> Void = { _ in },
    ) async throws -> ImportSummary {
        let fileManager = FileManager.default
        let staging = root.appending(path: ".staging/\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        let scoped = items.filter { $0.startAccessingSecurityScopedResource() }
        defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }

        var summary = ImportSummary()
        let unzipped = staging.appendingPathExtension("zips")
        defer { try? fileManager.removeItem(at: unzipped) }
        let expanded = try unzip(items, into: unzipped, failures: &summary.failures)
        let audio = try copy(expanded, into: staging, movingFrom: unzipped, failures: &summary.failures, progress: progress)

        // ponytail: probed one at a time; a TaskGroup if big imports read slowly
        var probes: [String: ProbeResult] = [:]
        for (count, path) in audio.enumerated() {
            try Task.checkCancellation()
            do {
                let probe = try await AudioProbe.probe(staging.appending(path: path))
                if let duration = probe.duration, duration > 0 {
                    probes[path] = probe
                } else {
                    summary.failures.append(ImportFailure(path: path, reason: "Couldn't tell how long this file is."))
                }
            } catch {
                summary.failures.append(ImportFailure(path: path, reason: Self.reason(for: error)))
            }
            progress(ImportProgress(phase: .reading, completed: count + 1, total: audio.count))
        }

        let groups = BookGrouping.group(probes.map { path, probe in
            GroupingFile(
                path: path, album: probe.album, artist: probe.author, trackNumber: probe.trackNumber, discNumber: probe.discNumber,
                duration: probe.duration ?? 0, hasChapters: !probe.chapters.isEmpty, isMP4: probe.format == .mp4,
            )
        })
        summary.bookIDs = try save(groups, probes: probes, staging: staging, progress: progress)

        if removingSources {
            for item in items {
                try? fileManager.removeItem(at: item)
            }
        }
        return summary
    }

    // MARK: - Copying

    /// A file to copy into staging, at `path` under it.
    private struct CopyEntry {
        var source: URL
        var path: String
        var isAudio: Bool
    }

    /// Copies the audio, cue sheets and images in `items` into `staging`, each item under its own (de-duplicated) name.
    /// Files under `extracted` are already ours, so they're moved instead.
    /// - Returns: The copied audio, relative to `staging`.
    private func copy(
        _ items: [URL], into staging: URL, movingFrom extracted: URL, failures: inout [ImportFailure],
        progress: @Sendable (ImportProgress) -> Void,
    ) throws -> [String] {
        let fileManager = FileManager.default
        let extractedPath = extracted.standardizedFileURL.path + "/"
        func isExtracted(_ url: URL) -> Bool {
            url.standardizedFileURL.path.hasPrefix(extractedPath)
        }

        let plan = Self.plan(items, failures: &failures)
        let needed = plan.reduce(Int64(0)) { total, entry in
            isExtracted(entry.source) ? total : total + Int64((try? entry.source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        let available = try availableCapacity(root)
        guard needed <= available else { throw ImportError.insufficientSpace(needed: needed, available: available) }

        var audio: [String] = []
        for (count, entry) in plan.enumerated() {
            try Task.checkCancellation()
            let destination = staging.appending(path: entry.path)
            do {
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if isExtracted(entry.source) {
                    try fileManager.moveItem(at: entry.source, to: destination)
                } else {
                    try fileManager.copyItem(at: entry.source, to: destination)
                }
                if entry.isAudio {
                    audio.append(entry.path)
                }
            } catch {
                failures.append(ImportFailure(path: entry.path, reason: error.localizedDescription))
            }
            progress(ImportProgress(phase: .copying, completed: count + 1, total: plan.count))
        }
        return audio
    }

    /// What to copy from `items`: audio, cue sheets and images, walking into folders. Reports files that can't be imported.
    private static func plan(_ items: [URL], failures: inout [ImportFailure]) -> [CopyEntry] {
        var plan: [CopyEntry] = []
        func consider(_ file: URL, path: String, pickedDirectly: Bool) {
            let ext = file.pathExtension.lowercased()
            let isAudio = audioExtensions.contains(ext)
            if isAudio || imageExtensions.contains(ext) || ext == "cue" {
                plan.append(CopyEntry(source: file, path: path, isAudio: isAudio))
            } else if let unsupported = UnsupportedFormat(pathExtension: ext) {
                failures.append(ImportFailure(path: path, reason: unsupported.reason))
            } else if ext == "zip" {
                failures.append(ImportFailure(path: path, reason: "Zip archives inside folders aren't opened. Import the zip on its own."))
            } else if pickedDirectly {
                failures.append(ImportFailure(path: path, reason: "This isn't an audio file Ear Reader can play."))
            }
        }

        var names: Set<String> = []
        for item in items {
            let name = unique(item.lastPathComponent, in: &names)
            guard (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                consider(item, path: name, pickedDirectly: true)
                continue
            }
            let base = item.resolvingSymlinksInPath().pathComponents.count
            let files = FileManager.default.enumerator(
                at: item,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: .skipsHiddenFiles,
            )
            while let file = files?.nextObject() as? URL {
                guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                let relative = file.resolvingSymlinksInPath().pathComponents.dropFirst(base).joined(separator: "/")
                consider(file, path: "\(name)/\(relative)", pickedDirectly: false)
            }
        }
        return plan
    }

    /// `"Book"`, then `"Book 2"`, `"Book 3"`… keeping the extension.
    private static func unique(_ name: String, in names: inout Set<String>) -> String {
        var candidate = name, number = 1
        while names.contains(candidate) {
            number += 1
            let ext = (name as NSString).pathExtension
            let stem = (name as NSString).deletingPathExtension
            candidate = ext.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(ext)"
        }
        names.insert(candidate)
        return candidate
    }

    // MARK: - Saving

    /// Moves each group's files into a book folder and saves the books in batches. On any error, unsaved books are
    /// rolled back and their folders removed.
    private func save(
        _ groups: [BookGroup], probes: [String: ProbeResult], staging: URL, progress: @Sendable (ImportProgress) -> Void,
    ) throws -> [UUID] {
        var saved: [UUID] = [], pending: [UUID] = []
        do {
            for (count, group) in groups.enumerated() {
                try Task.checkCancellation()
                let id = UUID()
                pending.append(id) // before moving anything, so cleanup covers a half-moved book
                try insertBook(id: id, group: group, probes: probes, staging: staging)
                if pending.count >= Self.batchSize {
                    try modelContext.save()
                    saved += pending
                    pending = []
                }
                progress(ImportProgress(phase: .saving, completed: count + 1, total: groups.count))
            }
            try modelContext.save()
            return saved + pending
        } catch {
            modelContext.rollback()
            for id in pending {
                try? FileManager.default.removeItem(at: folder(for: id))
            }
            throw error
        }
    }

    private func insertBook(id: UUID, group: BookGroup, probes: [String: ProbeResult], staging: URL) throws {
        let fileManager = FileManager.default
        let folder = folder(for: id)
        var files: [AudioFile] = [], fileChapters: [FileChapters] = []
        for file in group.files {
            let probe = probes[file.path]!
            let relative = group.folder.isEmpty ? file.path : String(file.path.dropFirst(group.folder.count + 1))
            let destination = folder.appending(path: relative)
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: staging.appending(path: file.path), to: destination)
            files.append(AudioFile(relativePath: relative, duration: probe.duration ?? 0, format: probe.format.rawValue))
            let stem = ((relative as NSString).lastPathComponent as NSString).deletingPathExtension
            fileChapters.append(FileChapters(
                duration: probe.duration ?? 0, title: probe.trackTitle ?? stem, chapters: probe.chapters.map { ($0.start, $0.title) },
            ))
        }

        // Folder images (including the book folder's, above any disc folders), for the cover pipeline.
        // Copied, not moved: books split from one folder share them.
        let directories = Set([""] + files.map { ($0.relativePath as NSString).deletingLastPathComponent })
        for directory in directories {
            let stagedDirectory = staging.appending(path: group.folder).appending(path: directory)
            let images = (try? fileManager.contentsOfDirectory(at: stagedDirectory, includingPropertiesForKeys: nil)) ?? []
            for image in images where Self.imageExtensions.contains(image.pathExtension.lowercased()) {
                try? fileManager.copyItem(at: image, to: folder.appending(path: directory).appending(path: image.lastPathComponent))
            }
        }

        let tags = group.files.map { probes[$0.path]! }
        func tag<Value>(_ key: KeyPath<ProbeResult, Value?>) -> Value? {
            tags.lazy.compactMap { $0[keyPath: key] }.first
        }
        // One file's title falls back to its track title; a folder's to the folder name, not its first track
        let title = (tags.count == 1 ? tag(\.title) : tag(\.album)) ?? group.name
        let book = Book(id: id, title: title, files: files, chapters: Chapter.normalized(fileChapters))

        let record = BookRecord(
            id: id, title: title, authors: tag(\.author).map { [$0] } ?? [], narrators: tag(\.narrator).map { [$0] } ?? [],
            series: tag(\.series), seriesIndex: tag(\.seriesIndex), summary: tag(\.description), year: tag(\.year),
            genre: tag(\.genre), publisher: tag(\.publisher), duration: book.duration, needsReview: group.needsReview,
        )
        modelContext.insert(record)
        record.files = book.files.enumerated().map { index, file in
            FileRecord(
                index: index, relativePath: file.relativePath, duration: file.duration, globalOffset: file.globalOffset,
                format: file.format,
            )
        }
        record.chapters = book.chapters.map { ChapterRecord(index: $0.index, title: $0.title, start: $0.start, end: $0.end) }
    }

    static func reason(for error: any Error) -> String {
        switch error {
        case let unsupported as UnsupportedFormat: unsupported.reason
        case is ParseError: "The file is damaged or isn't a supported audio format."
        default: error.localizedDescription
        }
    }
}

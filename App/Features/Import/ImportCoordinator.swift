import Foundation
import Library
import Observation
import SwiftData

/// Runs imports one after another, from every entry point, and publishes their progress.
@Observable final class ImportCoordinator {
    private(set) var isImporting = false
    private(set) var progress: ImportProgress?
    private(set) var lastSummary: ImportSummary?
    var lastError: String?

    private let importer: LibraryImporter
    private var queue: Task<Void, Never>?

    init(container: ModelContainer) {
        importer = LibraryImporter(modelContainer: container)
    }

    /// From the file picker.
    func importPicked(_ urls: [URL]) {
        enqueue(removingSources: false) { urls }
    }

    /// "Open in…", the share sheet and AirDrop. With `LSSupportsOpeningDocumentsInPlace` off, iOS hands us a copy
    /// in `Documents/Inbox`, which the Documents scan moves into the library; anything else is imported as picked.
    func open(_ url: URL) {
        if url.isFileURL, url.resolvingSymlinksInPath().path.hasPrefix(Self.documents.resolvingSymlinksInPath().path) {
            importSharedDocuments()
        } else {
            importPicked([url])
        }
    }

    /// Files added through Finder file sharing land in `Documents/`, and opened files in `Documents/Inbox`.
    /// Both move into the library: the originals are deleted once imported, or once reported as failed.
    func importSharedDocuments() {
        enqueue(removingSources: true) {
            Self.children(of: Self.documents).filter { $0.lastPathComponent != "Inbox" }
                + Self.children(of: Self.documents.appending(path: "Inbox"))
        }
    }

    /// `items` is evaluated when the import starts, so a queued Documents scan doesn't see files an earlier one took.
    private func enqueue(removingSources: Bool, items: @escaping () -> [URL]) {
        let previous = queue
        queue = Task {
            await previous?.value
            let urls = items()
            guard !urls.isEmpty else { return }
            isImporting = true
            defer {
                isImporting = false
                progress = nil
            }
            do {
                for try await event in importer.importEvents(urls, removingSources: removingSources) {
                    switch event {
                    case let .progress(update): progress = update
                    case let .finished(summary): lastSummary = summary
                    }
                }
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    private static var documents: URL {
        .documentsDirectory
    }

    private static func children(of directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
    }
}

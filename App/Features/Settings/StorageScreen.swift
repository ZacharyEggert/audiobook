import Library
import SwiftData
import SwiftUI

struct SettingsScreen: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    StorageScreen()
                } label: {
                    Label("Storage", systemImage: "internaldrive")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

/// What the library takes on this device, largest books first, with Remove Download and Delete (PLAN §5).
struct StorageScreen: View {
    @Environment(\.modelContext) private var context
    @Query private var books: [BookRecord]
    @State private var usage: [UUID: Int64] = [:]
    @State private var downloaded: Set<UUID> = []
    @State private var freeSpace: Int64?
    @State private var refresh = 0
    @State private var pendingDelete: BookRecord?
    @State private var error: String?

    private let files = LibraryFiles()

    var body: some View {
        let sorted = books.sorted { (usage[$0.id] ?? 0) > (usage[$1.id] ?? 0) }
        List {
            Section {
                LabeledContent("Audiobooks", value: Self.format(usage.values.reduce(0, +)))
                if let freeSpace {
                    LabeledContent("Free on This Device", value: Self.format(freeSpace))
                }
            } footer: {
                Text("Removing a download keeps the book, your place and bookmarks. Deleting a book removes all of them.")
            }
            if !sorted.isEmpty {
                Section("Books") {
                    ForEach(sorted) { book in
                        row(book)
                    }
                }
            }
        }
        .navigationTitle("Storage")
        .task(id: "\(books.map(\.id))\(refresh)") { await measure() }
        .confirmationDialog(
            "Delete \(pendingDelete?.displayTitle ?? "")?",
            isPresented: Binding { pendingDelete != nil } set: {
                if !$0 {
                    pendingDelete = nil
                }
            },
            titleVisibility: .visible,
            presenting: pendingDelete,
        ) { book in
            Button("Delete Book", role: .destructive) { delete(book) }
        } message: { _ in
            Text("This deletes the audio, your place and bookmarks on all your devices.")
        }
        .alert("Couldn't Free Space", isPresented: Binding { error != nil } set: { _ in error = nil }) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private func row(_ book: BookRecord) -> some View {
        let isDownloaded = downloaded.contains(book.id)
        return HStack(spacing: 12) {
            CoverView(bookID: book.id, coverRef: book.coverRef, title: book.displayTitle, size: .list, cornerRadius: 4)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(book.displayTitle).font(.subheadline).foregroundStyle(Theme.textPrimary).lineLimit(2)
                if !isDownloaded {
                    Text("Not downloaded").font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            Text(usage[book.id].map(Self.format) ?? "–")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = book }
            if isDownloaded {
                Button("Remove Download", systemImage: "icloud.and.arrow.down") { removeDownload(book) }
                    .tint(Theme.primary)
            }
        }
        .contextMenu {
            if isDownloaded {
                Button("Remove Download", systemImage: "icloud.and.arrow.down") { removeDownload(book) }
            }
            Button("Delete Book", systemImage: "trash", role: .destructive) { pendingDelete = book }
        }
    }

    private func measure() async {
        usage = await files.usage(of: books.map(\.id))
        downloaded = Set(books.filter { files.isDownloaded(bookID: $0.id, audioPaths: $0.orderedFiles.map(\.relativePath)) }.map(\.id))
        freeSpace = try? LibraryImporter.volumeCapacity(.documentsDirectory)
    }

    private func removeDownload(_ book: BookRecord) {
        do {
            try files.removeDownload(bookID: book.id, audioPaths: book.orderedFiles.map(\.relativePath))
        } catch {
            self.error = error.localizedDescription
        }
        refresh += 1
    }

    private func delete(_ book: BookRecord) {
        let id = book.id
        do {
            try context.deleteBook(book, files: files)
            CoverCache.remove(bookID: id)
        } catch {
            self.error = error.localizedDescription
        }
        refresh += 1
    }

    private static func format(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }
}

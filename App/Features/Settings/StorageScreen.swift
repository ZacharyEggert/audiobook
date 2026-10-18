import Library
import Playback
import SwiftData
import SwiftUI

struct SettingsScreen: View {
    @Environment(PlayerController.self) private var player
    @AppStorage(PlayerSettings.skipBackKey) private var skipBack = 15
    @AppStorage(PlayerSettings.skipForwardKey) private var skipForward = 30
    @AppStorage(PlayerSettings.defaultSpeedKey) private var defaultSpeed: Double = 1
    @AppStorage(PlayerSettings.smartRewindKey) private var smartRewind = true
    @AppStorage(PlayerSettings.bookmarkOnPreviousKey) private var bookmarkOnPrevious = false
    @AppStorage(PlayerSettings.autoPlayNextKey) private var autoPlayNext = false
    @AppStorage(PlayerSettings.nightTimerKey) private var nightTimer = false
    @AppStorage(PlayerSettings.nightStartKey) private var nightStart = 22
    @AppStorage(PlayerSettings.nightEndKey) private var nightEnd = 6
    @AppStorage(PlayerSettings.nightMinutesKey) private var nightMinutes = 30

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Skip Back", selection: $skipBack) {
                        ForEach(PlayerSettings.intervals, id: \.self) { Text("\($0) seconds").tag($0) }
                    }
                    Picker("Skip Forward", selection: $skipForward) {
                        ForEach(PlayerSettings.intervals, id: \.self) { Text("\($0) seconds").tag($0) }
                    }
                    Stepper(
                        "Default Speed \(PlaybackSpeed.clamp(Float(defaultSpeed)).formatted())×",
                        value: $defaultSpeed, in: Double(PlaybackSpeed.range.lowerBound) ... Double(PlaybackSpeed.range.upperBound),
                        step: Double(PlaybackSpeed.step),
                    )
                    Toggle("Smart Rewind", isOn: $smartRewind)
                    Toggle("Bookmark on Previous Track", isOn: $bookmarkOnPrevious)
                    Toggle("Auto-Play Next in Series", isOn: $autoPlayNext)
                } header: {
                    Text("Playback")
                } footer: {
                    Text(
                        "Smart Rewind backs up a few seconds when you resume, more the longer you were away. "
                            + "Default Speed applies to books without their own speed. "
                            +
                            "Bookmark on Previous Track makes the previous-track button on headphones and the lock screen add a bookmark.",
                    )
                }
                Section {
                    Toggle("Night Timer", isOn: $nightTimer)
                    if nightTimer {
                        Picker("From", selection: $nightStart) { ForEach(0 ..< 24, id: \.self) { Text(Self.hour($0)).tag($0) } }
                        Picker("Until", selection: $nightEnd) { ForEach(0 ..< 24, id: \.self) { Text(Self.hour($0)).tag($0) } }
                        Stepper("Stop after \(nightMinutes) minutes", value: $nightMinutes, in: 5 ... 120, step: 5)
                    }
                } header: {
                    Text("Sleep Timer")
                } footer: {
                    Text("Starts a sleep timer when you press play during these hours. Shake your phone to add time.")
                }
                NavigationLink {
                    StorageScreen()
                } label: {
                    Label("Storage", systemImage: "internaldrive")
                }
            }
            .navigationTitle("Settings")
            .onChange(of: [
                skipBack, skipForward, smartRewind ? 1 : 0, bookmarkOnPrevious ? 1 : 0, Int((defaultSpeed * 20).rounded()),
                nightTimer ? 1 : 0, nightStart, nightEnd, nightMinutes,
            ]) {
                PlayerSettings.apply(to: player)
            }
        }
    }
}

private extension SettingsScreen {
    static func hour(_ hour: Int) -> String {
        Calendar.current.date(from: DateComponents(hour: hour))?.formatted(date: .omitted, time: .shortened) ?? "\(hour):00"
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

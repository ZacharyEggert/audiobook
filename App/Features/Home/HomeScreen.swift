import Library
import Playback
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Continue Listening hero, then horizontal rows of books (PLAN §6 Screens).
struct HomeScreen: View {
    @Environment(ImportCoordinator.self) private var imports
    @Environment(PlayerController.self) private var player
    @Query private var books: [BookRecord]
    @Query private var progressRecords: [ProgressRecord]
    @State private var isPicking = false

    var body: some View {
        let progress = progressRecords.latestByBook
        let rows = HomeRows(books: books, progress: progress)
        NavigationStack {
            Group {
                if rows.isEmpty {
                    ContentUnavailableView {
                        Label("No Books", systemImage: "headphones")
                    } description: {
                        Text("Import audiobooks from Files, or add them with Finder.")
                    } actions: {
                        Button("Import") { isPicking = true }
                            .buttonStyle(.glassProminent)
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 24) {
                            if let hero = rows.hero {
                                ContinueListeningCard(book: hero, progress: BookProgress(book: hero, record: progress[hero.id]))
                            }
                            HomeRow(title: "Recently Added", books: rows.recentlyAdded, progress: progress)
                            HomeRow(title: "In Progress", books: rows.inProgress, progress: progress)
                            HomeRow(title: "Next in Series", books: rows.nextInSeries, progress: progress)
                            HomeRow(title: "Finished Recently", books: rows.finishedRecently, progress: progress)
                        }
                        .padding(.vertical)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if imports.isImporting {
                        ImportProgressView(progress: imports.progress)
                    } else {
                        Button("Import", systemImage: "plus") { isPicking = true }
                    }
                }
            }
            .navigationDestination(for: BookRecord.self) { BookDetailScreen(book: $0) }
            .fileImporter(isPresented: $isPicking, allowedContentTypes: [.audio, .folder, .zip], allowsMultipleSelection: true) { result in
                if case let .success(urls) = result {
                    imports.importPicked(urls)
                }
            }
        }
    }
}

/// The book to resume: cover, title, progress and a glass play button.
private struct ContinueListeningCard: View {
    let book: BookRecord
    let progress: BookProgress
    @Environment(PlayerController.self) private var player

    private var isCurrent: Bool {
        player.book?.id == book.id
    }

    var body: some View {
        NavigationLink(value: book) {
            HStack(spacing: 16) {
                CoverView(bookID: book.id, coverRef: book.coverRef, title: book.displayTitle, size: .player)
                    .frame(width: 120)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Continue Listening")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Text(book.displayTitle)
                        .font(.title3.bold())
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    if let author = book.displayAuthors.first {
                        Text(author)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    ProgressBar(fraction: progress.fraction)
                    Text(progress.summary)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding()
        .background(Theme.surface, in: .rect(cornerRadius: 20))
        .overlay(alignment: .bottomTrailing) {
            Button(
                isCurrent && player.isPlaying ? "Pause" : "Play",
                systemImage: isCurrent && player.isPlaying ? "pause.fill" : "play.fill",
            ) {
                play()
            }
            .labelStyle(.iconOnly)
            .font(.title2)
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .padding(12)
        }
        .padding(.horizontal)
    }

    private func play() {
        guard !isCurrent else { return player.toggle() }
        Task {
            await player.load(book.book, folder: LibraryFiles().folder(for: book.id), at: progress.position)
            player.play()
        }
    }
}

private struct HomeRow: View {
    let title: String
    let books: [BookRecord]
    let progress: [UUID: ProgressRecord]

    var body: some View {
        if !books.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(books) { book in
                            NavigationLink(value: book) {
                                BookCard(book: book, progress: BookProgress(book: book, record: progress[book.id]))
                                    .frame(width: 140)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

#Preview {
    let container = try! LibraryStore.makeContainer(directory: nil) // swiftlint:disable:this force_try
    HomeScreen()
        .environment(ImportCoordinator(container: container))
        .environment(PlayerController.preview())
        .modelContainer(container)
}

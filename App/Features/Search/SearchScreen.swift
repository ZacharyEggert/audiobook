import Library
import Playback
import SwiftData
import SwiftUI

/// The search tab: titles, authors, narrators, series and chapter titles, grouped (PLAN §6 Navigation).
struct SearchScreen: View {
    /// Shows the full player once a chapter result starts playing.
    var openPlayer: () -> Void = {}
    @Environment(PlayerController.self) private var player
    @Query private var books: [BookRecord]
    @Query private var progressRecords: [ProgressRecord]
    @State private var query = ""

    var body: some View {
        let results = SearchResults(query: query, books: books)
        let progress = progressRecords.latestByBook
        NavigationStack {
            List {
                if results.isEmpty {
                    emptyState
                }
                if !results.titles.isEmpty {
                    Section("Titles") {
                        ForEach(results.titles) { book in
                            NavigationLink(value: book) {
                                BookRow(book: book, progress: BookProgress(book: book, record: progress[book.id]))
                            }
                        }
                    }
                }
                groupSection("Authors", results.authors)
                groupSection("Narrators", results.narrators)
                groupSection("Series", results.series)
                if !results.chapters.isEmpty {
                    Section("Chapters") {
                        ForEach(results.chapters) { hit in
                            Button { open(hit) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hit.chapter.title)
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(hit.book.displayTitle)
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityHint("Plays from this chapter")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .listRowBackground(Theme.background)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Search")
            .navigationDestination(for: BookRecord.self) { BookDetailScreen(book: $0) }
            .navigationDestination(for: LibraryGroup.self) { GroupBooksScreen(group: $0) }
        }
        .searchable(text: $query, prompt: "Titles, authors, chapters")
    }

    @ViewBuilder private var emptyState: some View {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView(
                "Search Your Library",
                systemImage: "magnifyingglass",
                description: Text("Find books by title, author, narrator, series or chapter."),
            )
            .listRowSeparator(.hidden)
        } else {
            ContentUnavailableView.search(text: query)
                .listRowSeparator(.hidden)
        }
    }

    @ViewBuilder private func groupSection(_ title: String, _ groups: [LibraryGroup]) -> some View {
        if !groups.isEmpty {
            Section(title) {
                ForEach(groups) { group in
                    NavigationLink(value: group) {
                        LabeledContent(group.name) {
                            Text(group.count, format: .number).monospacedDigit()
                        }
                        .foregroundStyle(Theme.textPrimary)
                    }
                    .accessibilityValue("\(group.count) \(group.count == 1 ? "book" : "books")")
                }
            }
        }
    }

    /// Opens the book at the chapter's start, or jumps there when it's already loaded, and shows the player.
    private func open(_ hit: SearchResults.ChapterHit) {
        let start = hit.chapter.start
        Task {
            if player.book?.id == hit.book.id {
                await player.seek(to: start)
            } else {
                await player.load(hit.book.book, folder: LibraryFiles().folder(for: hit.book.id), at: start)
            }
            player.play()
            openPlayer()
        }
    }
}

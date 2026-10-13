import Library
import SwiftData
import SwiftUI

/// Cover extended behind the toolbar, metadata, description, chapters and files, with a floating Play button (PLAN §6).
struct BookDetailScreen: View {
    let book: BookRecord
    @Query private var progressRecords: [ProgressRecord]
    @State private var isSummaryExpanded = false

    init(book: BookRecord) {
        self.book = book
        let id = book.id
        _progressRecords = Query(filter: #Predicate { $0.bookID == id }, sort: \.updatedAt, order: .reverse)
    }

    private var progress: BookProgress {
        BookProgress(book: book, record: progressRecords.first)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if book.needsReview {
                    Label(
                        "These files had different album or artist tags, so they may not all belong to this book.",
                        systemImage: "exclamationmark.triangle",
                    )
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal)
                }
                if let summary = book.displaySummary, !summary.isEmpty {
                    description(summary)
                }
                details
                chapters
                files
            }
            .padding(.bottom, 96) // clear of the Play button
        }
        .background(Theme.background)
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            // ponytail: no action until the player lands in M4
            Button {} label: {
                Label(progress.status == .notStarted ? "Play" : "Resume", systemImage: "play.fill")
                    .font(.headline)
                    .padding(.horizontal, 24)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 16) {
            CoverView(bookID: book.id, coverRef: book.coverRef, title: book.displayTitle, size: .player, cornerRadius: 0)
                .backgroundExtensionEffect()
            VStack(spacing: 6) {
                Text(book.displayTitle)
                    .font(.title2.bold())
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                if !book.displayAuthors.isEmpty {
                    Text(book.displayAuthors.formatted(.list(type: .and)))
                        .font(.headline)
                        .foregroundStyle(Theme.accent)
                }
                if !book.displayNarrators.isEmpty {
                    Text("Narrated by \(book.displayNarrators.formatted(.list(type: .and)))")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                if progress.status != .notStarted {
                    HStack(spacing: 8) {
                        ProgressBar(fraction: progress.fraction, isFinished: progress.status == .finished).frame(width: 120)
                        Text(progress.summary).font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
        }
    }

    private func description(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(summary)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(isSummaryExpanded ? nil : 4)
            Button(isSummaryExpanded ? "Less" : "More") {
                withAnimation { isSummaryExpanded.toggle() }
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal)
    }

    private var details: some View {
        Section {
            VStack(spacing: 0) {
                if let series = book.displaySeries {
                    let index = book.displaySeriesIndex.map { ", Book \($0.formatted())" } ?? ""
                    DetailRow(label: "Series", value: series + index)
                }
                DetailRow(label: "Length", value: BookProgress.format(book.duration))
                if let year = book.year {
                    DetailRow(label: "Year", value: String(year))
                }
                if let genre = book.genre {
                    DetailRow(label: "Genre", value: genre)
                }
                if let publisher = book.publisher {
                    DetailRow(label: "Publisher", value: publisher)
                }
                DetailRow(label: "Added", value: book.dateAdded.formatted(date: .abbreviated, time: .omitted))
            }
            .card()
        } header: {
            SectionHeader("Details")
        }
    }

    private var chapters: some View {
        let chapters = book.orderedChapters
        return Section {
            LazyVStack(spacing: 0) {
                ForEach(chapters, id: \.index) { chapter in
                    DetailRow(label: chapter.title, value: BookProgress.format(chapter.end - chapter.start), leading: chapter.index + 1)
                        .accessibilityElement(children: .combine)
                }
            }
            .card()
        } header: {
            SectionHeader("\(chapters.count) \(chapters.count == 1 ? "Chapter" : "Chapters")")
        }
    }

    private var files: some View {
        let files = book.orderedFiles
        return Section {
            LazyVStack(spacing: 0) {
                ForEach(files, id: \.index) { file in
                    DetailRow(label: file.relativePath, value: "\(file.format.uppercased()) · \(BookProgress.format(file.duration))")
                }
            }
            .card()
        } header: {
            SectionHeader("\(files.count) \(files.count == 1 ? "File" : "Files")")
        }
    }
}

/// A label and value on one line, with an optional number in front (chapter lists).
private struct DetailRow: View {
    let label: String
    let value: String
    var leading: Int?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let leading {
                Text(leading, format: .number)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                    .frame(minWidth: 24, alignment: .trailing)
            }
            Text(label)
                .font(.subheadline)
                .foregroundStyle(leading == nil ? Theme.textSecondary : Theme.textPrimary)
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(leading == nil ? Theme.textPrimary : Theme.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 10)
        .padding(.horizontal)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading)
        }
    }
}

/// A section title above a card.
struct SectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.title3.bold())
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .accessibilityAddTraits(.isHeader)
    }
}

private extension View {
    /// Content on the solid surface layer; never glass (PLAN §6).
    func card() -> some View {
        background(Theme.surface, in: .rect(cornerRadius: 12))
            .clipShape(.rect(cornerRadius: 12))
            .padding(.horizontal)
    }
}

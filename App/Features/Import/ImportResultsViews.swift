import Library
import SwiftData
import SwiftUI

/// The toolbar's import indicator: a spinner and how far the current phase is.
struct ImportProgressView: View {
    let progress: ImportProgress?

    var body: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            if let progress, progress.total > 0 {
                Text("\(progress.completed)/\(progress.total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 6)
        .accessibilityElement()
        .accessibilityLabel("Importing")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard let progress else { return "" }
        let phase = switch progress.phase {
        case .copying: "Copying files"
        case .reading: "Reading files"
        case .saving: "Saving books"
        }
        return "\(phase), \(progress.completed) of \(progress.total)"
    }
}

/// After an import: the books it added, which of them need a look, and the files it couldn't take, with reasons.
struct ImportResultsSheet: View {
    let summary: ImportSummary
    @Environment(\.dismiss) private var dismiss
    @Query private var books: [BookRecord]

    init(summary: ImportSummary) {
        self.summary = summary
        let ids = summary.bookIDs
        _books = Query(filter: #Predicate { ids.contains($0.id) }, sort: \.title)
    }

    var body: some View {
        NavigationStack {
            List {
                let flagged = books.filter(\.needsReview)
                if !books.isEmpty {
                    Section("Imported \(books.count) \(books.count == 1 ? "Book" : "Books")") {
                        ForEach(books) { ImportedBookRow(book: $0) }
                    }
                }
                if !flagged.isEmpty {
                    Section {
                        ForEach(flagged) { ImportedBookRow(book: $0) }
                    } header: {
                        Text("Needs Review")
                    } footer: {
                        Text("These books' files had different album or artist tags, so they may be grouped wrong.")
                    }
                }
                if !summary.failures.isEmpty {
                    Section("Couldn't Import \(summary.failures.count) \(summary.failures.count == 1 ? "File" : "Files")") {
                        ForEach(Array(summary.failures.enumerated()), id: \.offset) { _, failure in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(failure.path).font(.subheadline).foregroundStyle(Theme.textPrimary)
                                Text(failure.reason).font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            .navigationTitle("Import Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ImportedBookRow: View {
    let book: BookRecord

    var body: some View {
        HStack(spacing: 12) {
            CoverView(bookID: book.id, coverRef: book.coverRef, title: book.displayTitle, size: .list, cornerRadius: 4)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(book.displayTitle).font(.subheadline).foregroundStyle(Theme.textPrimary)
                Text(
                    "\(book.orderedFiles.count) \(book.orderedFiles.count == 1 ? "file" : "files") · \(BookProgress.format(book.duration))",
                )
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

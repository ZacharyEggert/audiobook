import Library
import SwiftUI

/// A thin capsule: accent while listening, success once finished.
struct ProgressBar: View {
    let fraction: Double
    var isFinished = false

    var body: some View {
        Capsule()
            .fill(Theme.surfaceSecondary)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(isFinished ? Theme.success : Theme.accent)
                        .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
            }
            .frame(height: 4)
            .accessibilityElement()
            .accessibilityLabel("Progress")
            .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
    }
}

/// A list row: cover, title, author, narrator, progress and time left (PLAN §6 Library).
struct BookRow: View {
    let book: BookRecord
    let progress: BookProgress

    var body: some View {
        HStack(spacing: 12) {
            CoverView(bookID: book.id, coverRef: book.coverRef, title: book.displayTitle, size: .list)
                .frame(width: 60)
            VStack(alignment: .leading, spacing: 3) {
                Text(book.displayTitle)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                if !book.displayAuthors.isEmpty {
                    Text(book.displayAuthors.formatted(.list(type: .and)))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                if !book.displayNarrators.isEmpty {
                    Text("Narrated by \(book.displayNarrators.formatted(.list(type: .and)))")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    if progress.status == .inProgress {
                        ProgressBar(fraction: progress.fraction).frame(maxWidth: 80)
                    }
                    Text(progress.summary)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(progress.status == .finished ? Theme.success : Theme.textSecondary)
                }
                .padding(.top, 2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A grid cell: cover, title, author and progress.
struct BookCard: View {
    let book: BookRecord
    let progress: BookProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverView(bookID: book.id, coverRef: book.coverRef, title: book.displayTitle, size: .grid)
            if progress.status != .notStarted {
                ProgressBar(fraction: progress.fraction, isFinished: progress.status == .finished)
            }
            Text(book.displayTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
            if let author = book.displayAuthors.first {
                Text(author)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(progress.summary)
    }
}

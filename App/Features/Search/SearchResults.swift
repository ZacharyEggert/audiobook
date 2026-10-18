import Foundation
import Library

/// Library matches for a search query, grouped by what matched (PLAN §6 Navigation).
struct SearchResults {
    /// A chapter whose title matched, with the book it belongs to.
    struct ChapterHit: Identifiable {
        var book: BookRecord
        var chapter: ChapterRecord

        var id: String {
            "\(book.id)-\(chapter.index)"
        }
    }

    static let chapterLimit = 50

    var titles: [BookRecord] = []
    var authors: [LibraryGroup] = []
    var narrators: [LibraryGroup] = []
    var series: [LibraryGroup] = []
    var chapters: [ChapterHit] = []

    var isEmpty: Bool {
        titles.isEmpty && authors.isEmpty && narrators.isEmpty && series.isEmpty && chapters.isEmpty
    }

    /// Case- and diacritic-insensitive; a blank query matches nothing.
    init(query: String, books: [BookRecord]) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        func matches(_ text: String) -> Bool {
            text.localizedStandardContains(query)
        }
        let sorted = books.sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
        titles = sorted.filter { matches($0.displayTitle) }
        authors = Self.groups(.author, in: sorted, matching: matches) { $0.displayAuthors }
        narrators = Self.groups(.narrator, in: sorted, matching: matches) { $0.displayNarrators }
        series = Self.groups(.series, in: sorted, matching: matches) { $0.displaySeries.map { [$0] } ?? [] }
        chapters = Array(
            sorted.lazy
                .flatMap { book in book.orderedChapters.lazy.filter { matches($0.title) }.map { ChapterHit(book: book, chapter: $0) } }
                .prefix(Self.chapterLimit),
        )
    }

    private static func groups(
        _ kind: LibraryGroup.Kind,
        in books: [BookRecord],
        matching matches: (String) -> Bool,
        names: (BookRecord) -> [String],
    ) -> [LibraryGroup] {
        var counts: [String: Int] = [:]
        for book in books {
            for name in names(book) where matches(name) {
                counts[name, default: 0] += 1
            }
        }
        return counts
            .map { LibraryGroup(kind: kind, name: $0.key, count: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

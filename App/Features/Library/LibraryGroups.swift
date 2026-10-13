import Library
import SwiftData
import SwiftUI

/// One author, narrator, series or collection, to drill into.
struct LibraryGroup: Hashable, Identifiable {
    enum Kind: Hashable {
        case author, narrator, series
        case collection(UUID)
    }

    var kind: Kind
    var name: String
    var count = 0

    var id: Self {
        self
    }
}

extension [BookRecord] {
    /// Authors, narrators or series, by name, with how many books each has. A book with no author or narrator is
    /// grouped under "Unknown"; one with no series isn't in any.
    func groups(_ kind: LibraryGroup.Kind) -> [LibraryGroup] {
        var counts: [String: Int] = [:]
        for book in self {
            for name in book.groupNames(kind) {
                counts[name, default: 0] += 1
            }
        }
        return counts
            .map { LibraryGroup(kind: kind, name: $0.key, count: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The group's books: a series by its index (unnumbered last), a collection in its own order, others by title.
    func books(in group: LibraryGroup, collections: [CollectionRecord]) -> [BookRecord] {
        func byTitle(_ a: BookRecord, _ b: BookRecord) -> Bool {
            a.displayTitle.localizedStandardCompare(b.displayTitle) == .orderedAscending
        }
        switch group.kind {
        case let .collection(id):
            let byID = Dictionary(map { ($0.id, $0) }) { first, _ in first }
            return collections.first { $0.id == id }?.bookIDs.compactMap { byID[$0] } ?? []
        case .series:
            return filter { $0.displaySeries == group.name }.sorted { a, b in
                let (left, right) = (a.displaySeriesIndex ?? .infinity, b.displaySeriesIndex ?? .infinity)
                return left == right ? byTitle(a, b) : left < right
            }
        case .author, .narrator:
            return filter { $0.groupNames(group.kind).contains(group.name) }.sorted(by: byTitle)
        }
    }
}

private extension BookRecord {
    func groupNames(_ kind: LibraryGroup.Kind) -> [String] {
        switch kind {
        case .author: displayAuthors.isEmpty ? ["Unknown Author"] : displayAuthors
        case .narrator: displayNarrators.isEmpty ? ["Unknown Narrator"] : displayNarrators
        case .series: displaySeries.map { [$0] } ?? []
        case .collection: []
        }
    }
}

/// The Authors, Series, Narrators and Collections tabs: names with counts.
struct GroupListView: View {
    let tab: LibraryTab
    @Query private var books: [BookRecord]
    @Query(sort: \CollectionRecord.name) private var collections: [CollectionRecord]

    var body: some View {
        let groups = groups
        if groups.isEmpty {
            ContentUnavailableView(emptyTitle, systemImage: emptyImage, description: Text(emptyDescription))
        } else {
            List(groups) { group in
                NavigationLink(value: group) {
                    LabeledContent(group.name) {
                        Text(group.count, format: .number).monospacedDigit()
                    }
                    .foregroundStyle(Theme.textPrimary)
                }
                .accessibilityValue("\(group.count) \(group.count == 1 ? "book" : "books")")
                .listRowBackground(Theme.background)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var groups: [LibraryGroup] {
        switch tab {
        case .titles: []
        case .authors: books.groups(.author)
        case .narrators: books.groups(.narrator)
        case .series: books.groups(.series)
        case .collections:
            collections.map { collection in
                let group = LibraryGroup(kind: .collection(collection.id), name: collection.name)
                return LibraryGroup(kind: group.kind, name: group.name, count: books.books(in: group, collections: collections).count)
            }
        }
    }

    private var emptyTitle: String {
        "No \(tab.label)"
    }

    private var emptyImage: String {
        switch tab {
        case .collections: "rectangle.stack"
        case .series: "books.vertical"
        default: "person.2"
        }
    }

    private var emptyDescription: String {
        switch tab {
        case .collections: "Collections you make will appear here."
        case .series: "Books tagged with a series will appear here."
        default: "Import audiobooks to see them here."
        }
    }
}

/// The books in one author, narrator, series or collection.
struct GroupBooksScreen: View {
    let group: LibraryGroup
    @Query private var books: [BookRecord]
    @Query private var collections: [CollectionRecord]
    @Query private var progressRecords: [ProgressRecord]

    var body: some View {
        let progress = progressRecords.latestByBook
        List(books.books(in: group, collections: collections)) { book in
            NavigationLink(value: book) {
                VStack(alignment: .leading, spacing: 4) {
                    if group.kind == .series, let index = book.displaySeriesIndex {
                        Text("Book \(index.formatted())")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    BookRow(book: book, progress: BookProgress(book: book, record: progress[book.id]))
                }
            }
            .listRowBackground(Theme.background)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .overlay {
            if books.books(in: group, collections: collections).isEmpty {
                ContentUnavailableView("No Books", systemImage: "books.vertical")
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

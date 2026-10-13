import Library
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum LibraryTab: String, CaseIterable, Identifiable {
    case titles, authors, series, narrators, collections

    var id: Self {
        self
    }

    var label: String {
        switch self {
        case .titles: "Titles"
        case .authors: "Authors"
        case .series: "Series"
        case .narrators: "Narrators"
        case .collections: "Collections"
        }
    }
}

/// Titles · Authors · Series · Narrators · Collections, picked from a segmented control in the top bar (PLAN §6).
struct LibraryScreen: View {
    @Environment(ImportCoordinator.self) private var imports
    @AppStorage("library.tab") private var tab = LibraryTab.titles
    @State private var isPicking = false

    var body: some View {
        NavigationStack {
            Group {
                switch tab {
                case .titles: TitlesView(isPicking: $isPicking)
                default: ContentUnavailableView(tab.label, systemImage: "books.vertical", description: Text("Coming soon"))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .navigationTitle("Library")
            .safeAreaBar(edge: .top) {
                Picker("Library View", selection: $tab) {
                    ForEach(LibraryTab.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if imports.isImporting {
                        ProgressView()
                    } else {
                        Button("Import", systemImage: "plus") { isPicking = true }
                    }
                }
            }
            .fileImporter(isPresented: $isPicking, allowedContentTypes: [.audio, .folder, .zip], allowsMultipleSelection: true) { result in
                if case let .success(urls) = result {
                    imports.importPicked(urls)
                }
            }
            .alert("Import Failed", isPresented: Binding { imports.lastError != nil } set: { _ in imports.lastError = nil }) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(imports.lastError ?? "")
            }
        }
    }
}

/// Every book, as a list or a grid, sorted and filtered from the toolbar menu.
private struct TitlesView: View {
    @Binding var isPicking: Bool
    @Query private var books: [BookRecord]
    @Query private var progressRecords: [ProgressRecord]
    @AppStorage("library.sort") private var sort = LibrarySort.recent
    @AppStorage("library.filter") private var filter = LibraryFilter.all
    @AppStorage("library.grid") private var isGrid = false

    var body: some View {
        let progress = progressRecords.latestByBook
        let shown = books.arranged(sort: sort, filter: filter, progress: progress)
        Group {
            if books.isEmpty {
                ContentUnavailableView {
                    Label("No Books", systemImage: "books.vertical")
                } description: {
                    Text("Import audiobooks from Files, or add them with Finder.")
                } actions: {
                    Button("Import") { isPicking = true }
                        .buttonStyle(.glassProminent)
                }
            } else if shown.isEmpty {
                ContentUnavailableView {
                    Label("No \(filter.label) Books", systemImage: "line.3.horizontal.decrease")
                } actions: {
                    Button("Show All") { filter = .all }
                }
            } else if isGrid {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16, alignment: .top)], spacing: 20) {
                        ForEach(shown) { book in
                            NavigationLink(value: book) {
                                BookCard(book: book, progress: BookProgress(book: book, record: progress[book.id]))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            } else {
                List(shown) { book in
                    NavigationLink(value: book) {
                        BookRow(book: book, progress: BookProgress(book: book, record: progress[book.id]))
                    }
                    .listRowBackground(Theme.background)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu("Sort and Filter", systemImage: "line.3.horizontal.decrease") {
                    Picker("Sort", selection: $sort) {
                        ForEach(LibrarySort.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Show", selection: $filter) {
                        ForEach(LibraryFilter.allCases) { Text($0.label).tag($0) }
                    }
                }
                .disabled(books.isEmpty)
            }
            ToolbarItem(placement: .topBarLeading) {
                Button(isGrid ? "Show as List" : "Show as Grid", systemImage: isGrid ? "list.bullet" : "square.grid.2x2") {
                    isGrid.toggle()
                }
                .disabled(books.isEmpty)
            }
        }
    }
}

extension [ProgressRecord] {
    /// One record per book; the newest wins if sync left duplicates.
    var latestByBook: [UUID: ProgressRecord] {
        Dictionary(map { ($0.bookID, $0) }) { $0.updatedAt >= $1.updatedAt ? $0 : $1 }
    }
}

#Preview {
    let container = try! LibraryStore.makeContainer(directory: nil) // swiftlint:disable:this force_try
    LibraryScreen()
        .environment(ImportCoordinator(container: container))
        .modelContainer(container)
}

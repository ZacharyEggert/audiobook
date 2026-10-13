import Library
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// ponytail: a plain title list so imports can be checked; the real Titles tab is roadmap 3.8.
struct LibraryScreen: View {
    @Environment(ImportCoordinator.self) private var imports
    @Query(sort: \BookRecord.dateAdded, order: .reverse) private var books: [BookRecord]
    @State private var isPicking = false

    var body: some View {
        NavigationStack {
            List(books) { book in
                VStack(alignment: .leading) {
                    Text(book.title).font(.headline)
                    Text(book.authors.joined(separator: ", ")).font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
            }
            .overlay {
                if books.isEmpty {
                    ContentUnavailableView {
                        Label("No Books", systemImage: "books.vertical")
                    } description: {
                        Text("Import audiobooks from Files, or add them with Finder.")
                    } actions: {
                        Button("Import") { isPicking = true }
                            .buttonStyle(.glassProminent)
                    }
                }
            }
            .navigationTitle("Library")
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

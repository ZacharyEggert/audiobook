import AudiobookCore
import Library
import Playback
import SwiftData
import SwiftUI

/// The loaded book's bookmarks with chapter and time; tap to jump, swipe to delete, edit the note (PLAN §5 Player).
struct BookmarksSheet: View {
    @Environment(PlayerController.self) private var player
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var bookmarks: [BookmarkRecord]
    @State private var editing: BookmarkRecord?
    @State private var note = ""

    init(bookID: UUID) {
        _bookmarks = Query(
            filter: #Predicate<BookmarkRecord> { $0.bookID == bookID },
            sort: [SortDescriptor(\.position), SortDescriptor(\.createdAt)],
        )
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(bookmarks) { bookmark in
                    Button {
                        Task { await player.seek(to: bookmark.position) }
                        dismiss()
                    } label: {
                        row(bookmark)
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { Bookmarks.delete(bookmark, in: context) }
                        Button("Edit", systemImage: "pencil") { edit(bookmark) }.tint(Theme.accent)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .overlay {
                if bookmarks.isEmpty {
                    ContentUnavailableView("No Bookmarks", systemImage: "bookmark", description: Text("Add one from the player."))
                }
            }
            .navigationTitle("Bookmarks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
            .alert("Bookmark Note", isPresented: Binding { editing != nil } set: {
                if !$0 {
                    editing = nil
                }
            }) {
                TextField("Note", text: $note)
                Button("Save") {
                    if let editing {
                        Bookmarks.update(editing, note: note, in: context)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func edit(_ bookmark: BookmarkRecord) {
        note = bookmark.note ?? ""
        editing = bookmark
    }

    private func row(_ bookmark: BookmarkRecord) -> some View {
        let chapter = player.book?.chapters.last { $0.start <= bookmark.position }
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(bookmark.note ?? chapter?.title ?? "Bookmark")
                    .foregroundStyle(Theme.textPrimary)
                if bookmark.note != nil, let chapter {
                    Text(chapter.title)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 12)
            Text(BookProgress.clock(bookmark.position))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

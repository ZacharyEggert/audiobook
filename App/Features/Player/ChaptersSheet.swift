import AudiobookCore
import Playback
import SwiftUI

/// The loaded book's chapters with durations and progress, scrolled to the current one; tap to jump (PLAN §5 Player).
struct ChaptersSheet: View {
    @Environment(PlayerController.self) private var player
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List(player.book?.chapters ?? [], id: \.index) { chapter in
                    Button {
                        Task { await player.jump(to: chapter) }
                        dismiss()
                    } label: {
                        ChapterRow(chapter: chapter, position: player.position, isCurrent: chapter.index == player.chapter?.index)
                    }
                    .id(chapter.index)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onAppear {
                    if let current = player.chapter?.index {
                        proxy.scrollTo(current, anchor: .center)
                    }
                }
            }
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Number, title, duration and how far into the chapter playback is.
struct ChapterRow: View {
    let chapter: Chapter
    let position: TimeInterval
    let isCurrent: Bool

    private var fraction: Double {
        chapter.duration > 0 ? min(max((position - chapter.start) / chapter.duration, 0), 1) : 0
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(chapter.index + 1, format: .number)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .frame(minWidth: 24, alignment: .trailing)
            VStack(alignment: .leading, spacing: 6) {
                Text(chapter.title)
                    .font(isCurrent ? .body.weight(.semibold) : .body)
                    .foregroundStyle(isCurrent ? Theme.accent : fraction >= 1 ? Theme.textSecondary : Theme.textPrimary)
                if isCurrent {
                    ProgressBar(fraction: fraction)
                }
            }
            Spacer(minLength: 12)
            if fraction >= 1, !isCurrent {
                Image(systemName: "checkmark")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityLabel("Played")
            }
            Text(BookProgress.clock(chapter.duration))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

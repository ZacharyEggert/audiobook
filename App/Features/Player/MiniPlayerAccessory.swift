import Playback
import SwiftUI

/// The mini player in the tab bar's bottom accessory: cover, title and chapter, play/pause and skip forward.
/// Inline (tab bar minimized) drops the chapter and skip (PLAN §6 Navigation).
struct MiniPlayerAccessory: View {
    let open: () -> Void
    @Environment(PlayerController.self) private var player
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        if let book = player.book {
            let isInline = placement == .inline
            HStack(spacing: 12) {
                Button(action: open) {
                    HStack(spacing: 10) {
                        CoverView(bookID: book.id, coverRef: book.coverRef, title: book.title, size: .list, cornerRadius: 6)
                            .frame(width: isInline ? 28 : 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(book.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            if !isInline, let chapter = player.chapter {
                                Text(chapter.title)
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("Now playing: \(book.title)"))
                .accessibilityValue(player.chapter?.title ?? "")
                .accessibilityHint("Opens the player")

                Button(player.isPlaying ? "Pause" : "Play", systemImage: player.isPlaying ? "pause.fill" : "play.fill") {
                    player.toggle()
                }
                .contentTransition(.symbolEffect(.replace))
                if !isInline {
                    Button(
                        "Skip forward \(Int(player.skipForwardInterval)) seconds",
                        systemImage: "goforward.\(Int(player.skipForwardInterval))",
                    ) {
                        Task { await player.skipForward() }
                    }
                }
            }
            .labelStyle(.iconOnly)
            .font(.title3)
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, isInline ? 12 : 16)
        }
    }
}

#Preview {
    TabView {
        Tab("Library", systemImage: "books.vertical") { Theme.background }
    }
    .tabViewBottomAccessory { MiniPlayerAccessory {} }
    .environment(PlayerController.preview())
}

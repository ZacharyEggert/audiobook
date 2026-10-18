import AudiobookCore
import AVKit
import Playback
import SwiftUI

/// Cover-dominant player over a blurred cover backdrop, glass transport and a glass bottom toolbar (PLAN §6 Screens).
struct FullPlayerScreen: View {
    @Environment(PlayerController.self) private var player
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isShowingChapters = false
    @State private var isShowingSpeed = false
    @State private var isShowingSleep = false
    @State private var isShowingBookmarks = false
    /// Global book seconds while the scrubber is dragged; seeking waits for release.
    @State private var scrub: TimeInterval?

    var body: some View {
        NavigationStack {
            if let book = player.book {
                content(book)
                    .background { backdrop(book) }
                    .toolbar { toolbar }
                    .sheet(isPresented: $isShowingChapters) { ChaptersSheet() }
                    .sheet(isPresented: $isShowingSpeed) { SpeedSheet() }
                    .sheet(isPresented: $isShowingSleep) { SleepTimerSheet() }
                    .sheet(isPresented: $isShowingBookmarks) { BookmarksSheet(bookID: book.id) }
            }
        }
        .gesture(DragGesture().onEnded {
            if $0.translation.height > 120 {
                dismiss()
            }
        })
        .onChange(of: player.book == nil) { _, isEmpty in
            if isEmpty {
                dismiss()
            }
        }
    }

    private func content(_ book: Book) -> some View {
        let chapter = player.chapter ?? Chapter(index: 0, title: book.title, start: 0, end: book.duration)
        let title = scrub.flatMap { player.chapterTitle(at: $0) } ?? chapter.title
        return VStack(spacing: 20) {
            Spacer(minLength: 0)
            CoverView(bookID: book.id, coverRef: book.coverRef, title: book.title, size: .player, cornerRadius: 12)
                .padding(.horizontal, 12)
            VStack(spacing: 4) {
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(Theme.textPrimary)
                Text([book.title, book.authors.formatted(.list(type: .and))].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .lineLimit(1)
            .multilineTextAlignment(.center)
            ScrubberBar(scrub: $scrub)
            TransportCluster(isShowingSleep: $isShowingSleep)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
    }

    /// The cover, blurred and washed with the background so text keeps its contrast. Solid with Reduce Transparency.
    @ViewBuilder private func backdrop(_ book: Book) -> some View {
        if reduceTransparency {
            Theme.background.ignoresSafeArea()
        } else {
            // ponytail: blurred cover instead of a sampled colour; sample one if this reads muddy
            CoverView(bookID: book.id, coverRef: book.coverRef, title: book.title, size: .list, cornerRadius: 0)
                .scaledToFill()
                .blur(radius: 60)
                .overlay(Theme.background.opacity(0.6))
                .ignoresSafeArea()
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Close", systemImage: "chevron.down") { dismiss() }
        }
        ToolbarItemGroup(placement: .bottomBar) {
            Button { isShowingSpeed = true } label: {
                Text("\(player.rate.formatted())×").monospacedDigit()
            }
            .accessibilityLabel("Speed")
            .accessibilityValue("\(player.rate.formatted()) times")
            Spacer()
            Button("Chapters", systemImage: "list.bullet") { isShowingChapters = true }
            Spacer()
            Menu("Bookmark", systemImage: "bookmark") {
                Button("Add Bookmark", systemImage: "bookmark.fill") { player.addBookmark() }
                Button("Show Bookmarks", systemImage: "list.bullet") { isShowingBookmarks = true }
            }
            Spacer()
            RoutePicker()
                .frame(width: 32, height: 32)
                .accessibilityLabel("AirPlay")
        }
    }
}

/// Scrubber over the chapter or the whole book (tap the times to switch, remembered), with speed-adjusted time left.
private struct ScrubberBar: View {
    @Environment(PlayerController.self) private var player
    @AppStorage(PlayerSettings.scrubberModeKey) private var storedMode = ScrubberMode.chapter.rawValue
    /// Global book seconds while dragging; seeking waits for release.
    @Binding var scrub: TimeInterval?

    var body: some View {
        let mode = ScrubberMode(rawValue: storedMode) ?? .chapter
        let span = player.scrubberSpan(mode)
        let global = scrub ?? player.position
        let left = BookProgress.format(span.timeLeft(at: global, rate: player.rate))
        VStack(spacing: 4) {
            // Global seconds, so a scrub in either mode seeks straight to the value
            Slider(
                value: Binding { span.start + span.elapsed(at: global) } set: { scrub = $0 },
                in: span.start ... max(span.end, span.start + 1),
            ) { editing in
                guard !editing, let target = scrub else { return }
                Task {
                    await player.seek(to: target)
                    scrub = nil
                }
            }
            .accessibilityLabel(mode == .chapter ? "Chapter position" : "Book position")
            .accessibilityValue("\(BookProgress.clock(span.elapsed(at: global))) of \(BookProgress.clock(span.duration))")
            Button { storedMode = mode.toggled.rawValue } label: {
                HStack {
                    Text(BookProgress.clock(span.elapsed(at: global)))
                    Spacer()
                    Text("\(left) left in \(mode.rawValue)")
                    Spacer()
                    Text("-\(BookProgress.clock(span.remaining(at: global)))")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Time left in \(mode.rawValue)")
            .accessibilityValue(left)
            .accessibilityHint("Switches the scrubber to the \(mode.toggled.rawValue)")
        }
    }
}

/// Previous chapter, skip back, play/pause, skip forward and next chapter, morphing as one glass group.
struct TransportCluster: View {
    @Environment(PlayerController.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isShowingSleep: Bool
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: 16) {
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    Button("Previous Chapter", systemImage: "backward.end.fill") {
                        Task { await player.previousChapter() }
                    }
                    .frame(width: 44, height: 44)
                    skip(by: -player.skipBackInterval, symbol: "gobackward", label: "Skip back")
                    GlassPlayButton()
                    skip(by: player.skipForwardInterval, symbol: "goforward", label: "Skip forward")
                    Button("Next Chapter", systemImage: "forward.end.fill") {
                        Task { await player.nextChapter() }
                    }
                    .frame(width: 44, height: 44)
                    .disabled(player.chapter.map { $0.index == player.book?.chapters.last?.index } ?? true)
                }
                sleepControl
            }
            .labelStyle(.iconOnly)
            .foregroundStyle(Theme.textPrimary)
        }
        // No morph with Reduce Motion: the glass swaps instantly.
        .animation(reduceMotion ? nil : .smooth, value: player.sleepTimer.isActive)
    }

    /// A moon button that morphs into a countdown pill while the timer runs.
    @ViewBuilder private var sleepControl: some View {
        let timer = player.sleepTimer
        Button { isShowingSleep = true } label: {
            if let remaining = timer.remaining, timer.isActive {
                Label {
                    Text(Duration.seconds(remaining.rounded(.up)).formatted(.time(pattern: .hourMinuteSecond)))
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "moon.zzz.fill")
                }
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .glassEffect(.regular.interactive(), in: .capsule)
                .glassEffectID("sleep", in: glass)
            } else {
                Image(systemName: "moon.zzz")
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .glassEffectID("sleep", in: glass)
            }
        }
        .accessibilityLabel("Sleep Timer")
        .accessibilityValue(timer.remaining.flatMap { timer.isActive ? Self.spoken($0) : nil } ?? "Off")
    }

    private static func spoken(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds.rounded(.up)).formatted(.units(allowed: [.hours, .minutes, .seconds]))
    }

    private func skip(by seconds: TimeInterval, symbol: String, label: String) -> some View {
        let interval = Int(abs(seconds))
        return Button("\(label) \(interval) seconds", systemImage: "\(symbol).\(interval)") {
            Task { await player.skip(by: seconds) }
        }
        .font(.title2)
        .frame(width: 60, height: 60)
        .glassEffect(.regular.interactive(), in: .circle)
    }
}

/// The large play/pause button: navy-tinted interactive glass.
struct GlassPlayButton: View {
    @Environment(PlayerController.self) private var player

    var body: some View {
        Button(player.isPlaying ? "Pause" : "Play", systemImage: player.isPlaying ? "pause.fill" : "play.fill") {
            player.toggle()
        }
        .labelStyle(.iconOnly)
        .font(.system(size: 34))
        .contentTransition(.symbolEffect(.replace))
        .foregroundStyle(Theme.onPrimary)
        .frame(width: 84, height: 84)
        .glassEffect(.regular.tint(Theme.primary).interactive(), in: .circle)
    }
}

/// The system AirPlay route picker.
private struct RoutePicker: UIViewRepresentable {
    func makeUIView(context _: Context) -> AVRoutePickerView {
        AVRoutePickerView()
    }

    func updateUIView(_ view: AVRoutePickerView, context _: Context) {
        view.tintColor = UIColor(Theme.textPrimary)
        view.activeTintColor = UIColor(Theme.accent)
    }
}

extension PlayerController {
    /// A FakeEngine-backed controller with a twelve-chapter book loaded, for previews.
    static func preview() -> PlayerController {
        let player = PlayerController(engine: FakeEngine())
        let book = Book(
            title: "The Long Way Home", authors: ["Ada Palmer"],
            files: [AudioFile(relativePath: "book.m4b", duration: 3 * 3600, format: "mp4")],
            chapters: (0 ..< 12).map { Chapter(index: $0, title: "Chapter \($0 + 1)", start: Double($0) * 900, end: Double($0 + 1) * 900) },
        )
        Task { await player.load(book, folder: .temporaryDirectory, at: 2000) }
        return player
    }
}

#Preview {
    FullPlayerScreen().environment(PlayerController.preview())
}

#Preview("Sleep timer active") {
    let player = PlayerController.preview()
    player.startSleepTimer(.duration(25 * 60))
    return FullPlayerScreen().environment(player)
}

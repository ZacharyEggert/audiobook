import Library
import Playback
import SwiftData
import SwiftUI

@main
struct EarReaderApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let container: ModelContainer
    @State private var imports: ImportCoordinator
    @State private var player: PlayerController
    @State private var nowPlaying: NowPlaying
    @State private var audioSession: AudioSession
    @State private var shake = ShakeDetector()

    init() {
        do {
            container = try LibraryStore.makeContainer()
        } catch {
            fatalError("Couldn't open the library store: \(error)")
        }
        _imports = State(initialValue: ImportCoordinator(container: container))
        let player = PlayerController(makeEngine: { AVPlayerEngine() })
        PlayerSettings.apply(to: player)
        player.savedRate = { PlayerSettings.speed(for: $0) }
        player.onRateChange = { PlayerSettings.setSpeed($1, for: $0) }
        let context = container.mainContext
        player.onPositionSave = { PlaybackProgress.save(bookID: $0, position: $1, in: context) }
        player.onBookFinished = { id in PlaybackProgress.save(bookID: id, position: player.duration, finished: true, in: context) }
        player.onAddBookmark = { Bookmarks.add(bookID: $0, position: $1, in: context) }
        _player = State(initialValue: player)
        _nowPlaying = State(initialValue: NowPlaying(player: player) { book in
            await CoverCache.image(bookID: book.id, coverRef: book.coverRef, size: .player)?.cgImage
        })
        _audioSession = State(initialValue: AudioSession(player: player))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .tint(Theme.primary)
                .environment(imports)
                .environment(player)
                .onOpenURL { imports.open($0) }
                .task { await restoreLastBook() }
                .onChange(of: player.sleepTimer.isActive, initial: true) {
                    shake.onShake = { player.extendSleepTimer() }
                    if player.sleepTimer.isActive {
                        shake.start()
                    } else {
                        shake.stop()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                    player.saveNow()
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: imports.importSharedDocuments()
            case .background: player.saveNow()
            default: break
            }
        }
    }

    /// Loads the last book paused where it was left, so the mini player shows it.
    private func restoreLastBook() async {
        guard player.book == nil,
              let (record, position) = PlaybackProgress.lastBook(in: container.mainContext, files: LibraryFiles())
        else { return }
        await player.load(record.book, folder: LibraryFiles().folder(for: record.id), at: position)
    }
}

import AudiobookCore
import CoreGraphics
import Foundation
import MediaPlayer
#if canImport(UIKit)
    import UIKit
#else
    import AppKit
#endif

/// Lock screen, Control Center and headphone controls (PLAN §4, §5 System integration): publishes the player to
/// `MPNowPlayingInfoCenter` and routes `MPRemoteCommandCenter` back to it.
@MainActor public final class NowPlaying {
    /// Elapsed time and duration of the chapter rather than the whole book.
    public var usesChapterTime = true {
        didSet { update() }
    }

    private let player: PlayerController
    private let artwork: (Book) async -> CGImage?
    private var artworkBookID: UUID?
    private var artworkItem: MPMediaItemArtwork?

    /// - Parameter artwork: The book's cover, loaded once per book.
    public init(player: PlayerController, artwork: @escaping (Book) async -> CGImage?) {
        self.player = player
        self.artwork = artwork
        player.onTimingChange = { [weak self] in self?.update() }
        registerCommands()
        update()
    }

    /// Time and rate set here let the system extrapolate elapsed time, so this runs on discrete changes only.
    private func update() {
        let commands = MPRemoteCommandCenter.shared()
        commands.skipBackwardCommand.preferredIntervals = [NSNumber(value: player.skipBackInterval)]
        commands.skipForwardCommand.preferredIntervals = [NSNumber(value: player.skipForwardInterval)]
        guard let book = player.book else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        if book.id != artworkBookID {
            artworkBookID = book.id
            artworkItem = nil
            Task {
                let image = await artwork(book)
                guard artworkBookID == book.id, let image else { return }
                artworkItem = Self.artworkItem(image)
                update()
            }
        }
        var info = Self.info(for: player, usesChapterTime: usesChapterTime)
        info[MPMediaItemPropertyArtwork] = artworkItem
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func registerCommands() {
        let commands = MPRemoteCommandCenter.shared()
        let player = player
        func on(_ command: MPRemoteCommand, _ action: @escaping (MPRemoteCommandEvent) -> Void) {
            command.isEnabled = true
            command.addTarget { event in
                action(event)
                return .success
            }
        }
        on(commands.playCommand) { _ in player.play() }
        on(commands.pauseCommand) { _ in player.pause() }
        on(commands.togglePlayPauseCommand) { _ in player.toggle() }
        on(commands.skipBackwardCommand) { _ in Task { await player.skipBack() } }
        on(commands.skipForwardCommand) { _ in Task { await player.skipForward() } }
        on(commands.nextTrackCommand) { _ in Task { await player.nextChapter() } }
        on(commands.previousTrackCommand) { _ in Task { await player.previousChapter() } }
        on(commands.changePlaybackPositionCommand) { [weak self] event in
            guard let self, let event = event as? MPChangePlaybackPositionCommandEvent else { return }
            let target = Self.globalTime(remote: event.positionTime, player: player, usesChapterTime: usesChapterTime)
            Task { await player.seek(to: target) }
        }
        commands.changePlaybackRateCommand.supportedPlaybackRates = [0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3]
        on(commands.changePlaybackRateCommand) { event in
            guard let event = event as? MPChangePlaybackRateCommandEvent else { return }
            player.rate = event.playbackRate
        }
    }

    /// Now Playing for the player's book, without artwork: chapter title over book title and author.
    static func info(for player: PlayerController, usesChapterTime: Bool) -> [String: Any] {
        guard let book = player.book else { return [:] }
        let chapter = usesChapterTime ? player.chapter : nil
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: player.chapter?.title ?? book.title,
            MPMediaItemPropertyAlbumTitle: book.title,
            MPMediaItemPropertyArtist: book.authors.joined(separator: ", "),
            MPMediaItemPropertyPlaybackDuration: chapter?.duration ?? book.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: chapter.map { player.position - $0.start } ?? player.position,
            MPNowPlayingInfoPropertyPlaybackRate: player.isPlaying ? Double(player.rate) : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(player.rate),
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let index = player.chapter.flatMap({ chapter in book.chapters.firstIndex { $0.index == chapter.index } }) {
            info[MPNowPlayingInfoPropertyChapterNumber] = index
            info[MPNowPlayingInfoPropertyChapterCount] = book.chapters.count
        }
        return info
    }

    /// Book time for a lock screen scrub to `remote`, which is chapter time when Now Playing shows chapters.
    static func globalTime(remote: TimeInterval, player: PlayerController, usesChapterTime: Bool) -> TimeInterval {
        guard usesChapterTime, let chapter = player.chapter else { return remote }
        return chapter.start + min(remote, chapter.duration)
    }

    /// Nonisolated: MediaPlayer calls the handler off the main thread.
    private nonisolated static func artworkItem(_ image: CGImage) -> MPMediaItemArtwork {
        let size = CGSize(width: image.width, height: image.height)
        #if canImport(UIKit)
            let platformImage = UIImage(cgImage: image)
        #else
            let platformImage = NSImage(cgImage: image, size: size)
        #endif
        return MPMediaItemArtwork(boundsSize: size) { _ in platformImage }
    }
}

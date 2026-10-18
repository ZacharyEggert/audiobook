import AudiobookCore
import AVFoundation

/// Plays a book's files through an `AVQueuePlayer` holding the current file and the ones after it (PLAN §4).
@MainActor public final class AVPlayerEngine: PlaybackEngine {
    public private(set) var state: PlaybackState = .idle
    public var onEvent: ((PlaybackEvent) -> Void)?
    public var rate: Float = 1 {
        didSet {
            player.defaultRate = rate
            if state == .playing {
                player.rate = rate
            }
        }
    }

    public var volume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }

    let player = AVQueuePlayer()
    private var book: Book?
    private var folder: URL?
    /// The queued items: files `queueStart...` of the book.
    private(set) var items: [AVPlayerItem] = []
    private var queueStart = 0
    /// Last known global time, for while the queue is empty (rebuilding or ended).
    private var position: TimeInterval = 0
    private var statusObservations: [NSKeyValueObservation] = []
    private var timeObserver: Any?
    private var notificationTokens: [any NSObjectProtocol] = []

    public init() {
        // Local files: start at once rather than buffer
        player.automaticallyWaitsToMinimizeStalling = false
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        let center = NotificationCenter.default
        notificationTokens = [
            center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] note in
                let item = (note.object as AnyObject?).map(ObjectIdentifier.init)
                MainActor.assumeIsolated { self?.itemEnded(item) }
            },
            center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] note in
                let item = (note.object as AnyObject?).map(ObjectIdentifier.init)
                let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? any Error
                MainActor.assumeIsolated {
                    guard let self, self.items.contains(where: { ObjectIdentifier($0) == item }) else { return }
                    self.fail(error?.localizedDescription ?? "Playback failed")
                }
            },
        ]
    }

    isolated deinit {
        timeObserver.map(player.removeTimeObserver)
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
    }

    public var currentTime: TimeInterval {
        itemTime ?? position
    }

    public func load(_ book: Book, folder: URL, at global: TimeInterval) async throws {
        state = .idle
        self.book = book
        self.folder = folder
        let (index, local) = book.timeline.locate(global) ?? (0, 0)
        try await rebuild(at: index, local: local)
        set(.paused)
        position = currentTime
        onEvent?(.time(position))
    }

    public func play() {
        guard book != nil, state != .playing else { return }
        if state == .ended {
            set(.playing)
            Task { try? await rebuild(at: 0, local: 0) } // failures arrive through the item status observation
            return
        }
        set(.playing)
        player.play()
    }

    public func pause() {
        guard state == .playing else { return }
        player.pause()
        position = currentTime
        set(.paused)
    }

    // ponytail: overlapping seeks aren't serialized; PlayerController awaits each one. Add a generation check if UI scrubbing
    // ever fires seeks without awaiting.
    public func seek(to global: TimeInterval) async {
        guard let book, let (index, local) = book.timeline.locate(global) else { return }
        if state == .ended {
            set(.paused)
        }
        if index == currentIndex {
            await player.seek(to: cmTime(local), toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            try? await rebuild(at: index, local: local) // failures arrive through the item status observation
        }
        position = currentTime
        onEvent?(.time(position))
    }

    /// Book file index of the player's current item.
    private var currentIndex: Int? {
        items.firstIndex { $0 === player.currentItem }.map { queueStart + $0 }
    }

    private var itemTime: TimeInterval? {
        guard let book, let currentIndex else { return nil }
        return book.timeline.global(fileIndex: currentIndex, local: player.currentTime().seconds)
    }

    /// Queues files `index...`, waits for the first to be ready and seeks it exactly to `local`.
    /// ponytail: queues every remaining file. Window it if books with hundreds of files use too much memory.
    private func rebuild(at index: Int, local: TimeInterval) async throws {
        guard let book, let folder else { return }
        player.pause()
        player.removeAllItems()
        queueStart = index
        items = book.files[index...].map { file in
            let asset = AVURLAsset(
                url: folder.appending(path: file.relativePath),
                options: [AVURLAssetPreferPreciseDurationAndTimingKey: true],
            )
            let item = AVPlayerItem(asset: asset)
            item.audioTimePitchAlgorithm = .timeDomain
            player.insert(item, after: nil)
            return item
        }
        statusObservations = items.map { item in
            item.observe(\.status) { [weak self] item, _ in
                guard item.status == .failed else { return }
                let message = item.error?.localizedDescription ?? "Can't play this file"
                Task { @MainActor in self?.fail(message) }
            }
        }
        guard let first = items.first else { return }
        while first.status == .unknown {
            // ponytail: polls; local files are ready within a few milliseconds
            try await Task.sleep(for: .milliseconds(5))
        }
        if let error = first.error {
            throw error
        }
        await player.seek(to: cmTime(local), toleranceBefore: .zero, toleranceAfter: .zero)
        if state == .playing {
            player.play()
        } else if player.status == .readyToPlay {
            // ponytail: prerolls the current item; AVQueuePlayer buffers the next one itself, which keeps MP3
            // boundaries gapless with precise timing on
            _ = await player.preroll(atRate: rate)
        }
    }

    private func tick() {
        guard state != .idle, let time = itemTime else { return }
        position = time
        onEvent?(.time(time))
    }

    private func itemEnded(_ item: ObjectIdentifier?) {
        guard let book, let last = items.last, ObjectIdentifier(last) == item else { return }
        player.pause()
        position = book.duration
        onEvent?(.time(position))
        set(.ended)
    }

    private func fail(_ message: String) {
        guard state != .idle else { return } // `load` throws instead
        player.pause()
        set(.paused)
        onEvent?(.failed(message))
    }

    private func set(_ new: PlaybackState) {
        state = new
        onEvent?(.state(new))
    }

    private func cmTime(_ seconds: TimeInterval) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 44100)
    }
}

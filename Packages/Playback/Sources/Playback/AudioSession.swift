#if os(iOS)
    import AVFAudio
    import Foundation

    /// Configures `AVAudioSession` for spoken audio and forwards its notifications to the player as
    /// `AudioSessionEvent`s (PLAN §4). The decisions live in `PlayerController.handle(_:)`, where they're tested.
    @MainActor public final class AudioSession {
        private let player: PlayerController
        private var observers: [any NSObjectProtocol] = []

        public init(player: PlayerController) {
            self.player = player
            Self.configure()
            // Activating at launch would stop other apps' audio, so wait for play
            player.onWillPlay = { try? AVAudioSession.sharedInstance().setActive(true) }
            let center = NotificationCenter.default
            let session = AVAudioSession.sharedInstance()
            observers = [
                center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) {
                    let info = $0.userInfo
                    let type = (info?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
                    let options = AVAudioSession.InterruptionOptions(rawValue: info?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
                    switch type {
                    case .began: self.send(.interruptionBegan)
                    case .ended: self.send(.interruptionEnded(shouldResume: options.contains(.shouldResume)))
                    default: break
                    }
                },
                center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) {
                    let reason = ($0.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                        .flatMap(AVAudioSession.RouteChangeReason.init)
                    if reason == .oldDeviceUnavailable {
                        self.send(.oldDeviceUnavailable)
                    }
                },
                center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { _ in
                    Self.configure()
                    self.send(.mediaServicesReset)
                },
            ]
        }

        private nonisolated static func configure() {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        }

        private nonisolated func send(_ event: AudioSessionEvent) {
            Task { @MainActor in await player.handle(event) }
        }
    }
#endif

import MediaPlayer

/// Remote control commands from headphones, the lock screen and car steering wheels.
enum RemoteCommand: Sendable { case play, pause, toggle, next, previous }

@MainActor
protocol NowPlayingUpdating: AnyObject {
    var onCommand: ((RemoteCommand) -> Void)? { get set }
    func enable()
    func update(title: String, subtitle: String, isPlaying: Bool)
    func disable()
}

/// Lock-screen "Now Playing" info and `MPRemoteCommandCenter` wiring (FEATURES §2.2, §2.3).
@MainActor
final class NowPlayingController: NowPlayingUpdating {
    var onCommand: ((RemoteCommand) -> Void)?
    private var targets: [(MPRemoteCommand, Any)] = []

    func enable() {
        guard targets.isEmpty else { return }
        let center = MPRemoteCommandCenter.shared()
        let mapping: [(MPRemoteCommand, RemoteCommand)] = [
            (center.playCommand, .play),
            (center.pauseCommand, .pause),
            (center.togglePlayPauseCommand, .toggle),
            (center.nextTrackCommand, .next),
            (center.previousTrackCommand, .previous),
        ]
        for (command, action) in mapping {
            command.isEnabled = true
            let target = command.addTarget { [weak self] _ in
                MainActor.assumeIsolated { self?.onCommand?(action) }
                return .success
            }
            targets.append((command, target))
        }
    }

    func update(title: String, subtitle: String, isPlaying: Bool) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: subtitle,
            MPMediaItemPropertyAlbumTitle: "BuckleUp Quiz",
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
    }

    func disable() {
        for (command, target) in targets { command.removeTarget(target) }
        targets.removeAll()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}

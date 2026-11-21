import AVFoundation

/// Audio-session events the quiz reacts to (FEATURES §2.3, §2.4).
enum AudioSessionEvent: Sendable, Equatable {
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    /// The output device went away (headphones unplugged, car turned off).
    case outputLost
}

@MainActor
protocol AudioSessionControlling: AnyObject {
    var onEvent: ((AudioSessionEvent) -> Void)? { get set }
    func activateForListening(duckOthers: Bool) throws
    func deactivate()
}

/// Configures `AVAudioSession` once per session and never switches mode mid-session
/// (ADR-0008). Listen mode uses `.playback` over A2DP; Voice mode (M4) will use
/// `.playAndRecord` + `.voiceChat` over HFP.
@MainActor
final class AudioSessionController: AudioSessionControlling {
    var onEvent: ((AudioSessionEvent) -> Void)?
    private var observers: [NSObjectProtocol] = []

    func activateForListening(duckOthers: Bool) throws {
        let session = AVAudioSession.sharedInstance()
        // Ducking lowers music already playing instead of stopping it (configurable).
        let options: AVAudioSession.CategoryOptions = duckOthers
            ? [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
            : []
        try session.setCategory(.playback, mode: .spokenAudio, options: options)
        try session.setActive(true)
        observe()
    }

    func deactivate() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func observe() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            let options = AVAudioSession.InterruptionOptions(
                rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            MainActor.assumeIsolated {
                switch type {
                case .began: self?.onEvent?(.interruptionBegan)
                case .ended: self?.onEvent?(.interruptionEnded(shouldResume: options.contains(.shouldResume)))
                default: break
                }
            }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                .flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            MainActor.assumeIsolated {
                if reason == .oldDeviceUnavailable { self?.onEvent?(.outputLost) }
            }
        })
    }
}

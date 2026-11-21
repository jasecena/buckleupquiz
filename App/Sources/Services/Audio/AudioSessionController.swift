import AVFoundation

/// Audio-session events the quiz reacts to (FEATURES §2.3, §2.4).
enum AudioSessionEvent: Sendable, Equatable {
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    /// The output device went away (headphones unplugged, car turned off).
    case outputLost
}

/// Which microphone voice answers use (Settings → Answers).
enum MicPreference: String, Codable, CaseIterable, Sendable {
    /// A car, headset or plugged-in mic when there is one, otherwise the iPhone's.
    case automatic
    /// Always the iPhone's own mic. Car audio can stay in high quality (A2DP).
    case iPhone
}

@MainActor
protocol AudioSessionControlling: AnyObject {
    var onEvent: ((AudioSessionEvent) -> Void)? { get set }
    func activateForListening(duckOthers: Bool) throws
    /// Voice answers: play and record. Returns the microphone's name ("Using: <car>").
    func activateForVoice(duckOthers: Bool, mic: MicPreference) throws -> String?
    func deactivate()
}

/// Configures `AVAudioSession` once per session and never switches mode mid-session
/// (ADR-0008). Listen mode uses `.playback` over A2DP; voice answers use `.playAndRecord`
/// with the car/headset mic when there is one (ADR-0018).
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

    func activateForVoice(duckOthers: Bool, mic: MicPreference) throws -> String? {
        let session = AVAudioSession.sharedInstance()
        var options: AVAudioSession.CategoryOptions = [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
        if duckOthers { options.insert(.duckOthers) }
        try session.setCategory(.playAndRecord, mode: .default, options: options)
        try session.setActive(true)
        let inputs = session.availableInputs ?? []
        let external: Set<AVAudioSession.Port> = [.bluetoothHFP, .carAudio, .headsetMic, .usbAudio]
        let preferred = mic == .automatic
            ? inputs.first { external.contains($0.portType) } ?? inputs.first { $0.portType == .builtInMic }
            : inputs.first { $0.portType == .builtInMic }
        if let preferred { try? session.setPreferredInput(preferred) }
        observe()
        return session.currentRoute.inputs.first?.portName
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

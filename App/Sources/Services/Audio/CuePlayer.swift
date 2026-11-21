import AVFoundation

/// Non-speech sounds: the think-time tick and the "I'm listening" chime.
@MainActor
protocol CuePlaying: AnyObject {
    /// Called when a session starts. Keeps a quiet audio stream running so iOS does not
    /// suspend the app during silent think time with the screen locked (ADR-0008).
    func startSession()
    func endSession()
    func startThinking()
    func stopThinking()
    func play(_ cue: CueSound)
}

enum CueSound: Sendable { case listening }

/// Generates its sounds in code (no audio assets) and plays them through `AVAudioEngine`.
@MainActor
final class EngineCuePlayer: CuePlaying {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private lazy var silence = Self.buffer(format: format, seconds: 1) { _ in 0 }
    private lazy var tick = Self.buffer(format: format, seconds: 1) { t in
        // A soft 30 ms click once a second.
        t < 0.03 ? Float(sin(2 * .pi * 880 * t) * (1 - t / 0.03) * 0.12) : 0
    }
    private lazy var chime = Self.buffer(format: format, seconds: 0.35) { t in
        let freq = t < 0.15 ? 660.0 : 990.0
        let envelope = max(0, 1 - (t.truncatingRemainder(dividingBy: 0.175)) / 0.175)
        return Float(sin(2 * .pi * freq * t) * envelope * 0.25)
    }
    private var isRunning = false
    /// Whether the tick should be playing, so it comes back after the engine restarts.
    private var isTicking = false
    private var configObserver: NSObjectProtocol?

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func startSession() {
        guard !isRunning else { return }
        start()
        // Route changes (Bluetooth connecting) and the microphone switching on reconfigure the
        // audio hardware, which stops this engine: restart it, ticking again if it was.
        guard configObserver == nil else { return }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isRunning else { return }
                self.isRunning = false
                self.start()
            }
        }
    }

    private func start() {
        do {
            if !engine.isRunning {
                engine.connect(player, to: engine.mainMixerNode, format: format)
                try engine.start()
            }
            isRunning = true
            loop(isTicking ? tick : silence)
            player.play()
        } catch {
            isRunning = false
        }
    }

    func endSession() {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        player.stop()
        engine.stop()
        isRunning = false
        isTicking = false
    }

    func startThinking() {
        isTicking = true
        if isRunning { loop(tick) }
    }

    func stopThinking() {
        isTicking = false
        if isRunning { loop(silence) }
    }

    func play(_ cue: CueSound) {
        guard isRunning else { return }
        player.scheduleBuffer(chime, at: nil, options: .interrupts)
        player.scheduleBuffer(silence, at: nil, options: .loops)
    }

    private func loop(_ buffer: AVAudioPCMBuffer) {
        player.scheduleBuffer(buffer, at: nil, options: [.loops, .interrupts])
    }

    private static func buffer(format: AVAudioFormat, seconds: Double, sample: (Double) -> Float) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(format.sampleRate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let data = buffer.floatChannelData![0]
        for i in 0..<Int(frames) {
            data[i] = sample(Double(i) / format.sampleRate)
        }
        return buffer
    }
}

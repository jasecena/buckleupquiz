import AVFoundation

/// Gets the microphone's audio while a recogniser is listening. Called on the audio thread.
protocol MicConsumer: AnyObject, Sendable {
    func append(_ buffer: AVAudioPCMBuffer)
}

/// The microphone for voice answers (ADR-0028). iOS lets an app keep the microphone running in
/// the background but not start it there. So a game starts the mic once, while it's on screen,
/// and keeps it running until the game ends, which means answers are still heard with the
/// screen locked or another app open. Between answers the audio goes nowhere: it's only passed
/// to the recogniser while it listens, and it's never recorded or stored (ADR-0004).
@MainActor
final class MicInput {
    private var engine: AVAudioEngine?
    private var observer: NSObjectProtocol?
    private let sink = Sink()

    /// Starts the mic, or starts it again after a new car, a headset or a phone call stopped it.
    func start() throws {
        if let engine, engine.isRunning { return }
        stop()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw SpeechListenerError.micBusy("No microphone input (\(format.sampleRate) Hz, \(format.channelCount) channels).")
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tapBlock(feeding: sink))
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw SpeechListenerError.micBusy(error.localizedDescription)
        }
        self.engine = engine
        // A route change (the car connects, headphones come out) stops the engine. Start again
        // straight away, while the mic is still allowed to run in the background.
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { try? self?.start() }
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        sink.set(nil)
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
    }

    /// Who hears the mic now, or nil for nobody.
    func send(to consumer: (any MicConsumer)?) {
        sink.set(consumer)
    }

    /// Hands buffers from the audio thread to the current consumer.
    final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var consumer: (any MicConsumer)?

        func set(_ consumer: (any MicConsumer)?) {
            lock.withLock { self.consumer = consumer }
        }

        func append(_ buffer: AVAudioPCMBuffer) {
            lock.withLock { consumer }?.append(buffer)
        }
    }

    // Runs on the audio thread, so it's built outside the main actor.
    private nonisolated static func tapBlock(feeding sink: Sink) -> AVAudioNodeTapBlock {
        { buffer, _ in sink.append(buffer) }
    }
}

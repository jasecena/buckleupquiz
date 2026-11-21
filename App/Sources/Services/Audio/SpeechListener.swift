import AVFoundation
import Speech

/// Listens for one spoken reply (ADR-0018). Recognition runs on the device only (ADR-0004):
/// nothing is recorded, stored or sent anywhere.
@MainActor
protocol SpeechListening: AnyObject {
    /// Listens until the speaker pauses (about 1.2 s after speech) or `seconds` pass with no
    /// speech. Returns every alternative transcription, best first, or [] for silence.
    /// Cancelling the calling task stops listening at once.
    func listen(for seconds: Double, hints: [String]) async throws -> [String]
}

enum SpeechListenerError: Error {
    case unavailable
}

/// `SFSpeechRecognizer` on an `AVAudioEngine` input tap.
@MainActor
final class SystemSpeechListener: SpeechListening {
    /// How long a pause ends an answer.
    static let endOfSpeechSilence = 1.2
    /// Extra time allowed to finish an answer that started near the end of the window.
    static let overrun = 4.0

    private let recognizer: SFSpeechRecognizer

    /// nil when on-device recognition isn't available (we never fall back to Apple's servers).
    init?(preferredLocales: [Locale] = [Locale(identifier: "en-AU"), Locale(identifier: "en-US")]) {
        guard let recognizer = preferredLocales.lazy
            .compactMap({ SFSpeechRecognizer(locale: $0) })
            .first(where: { $0.supportsOnDeviceRecognition })
        else { return nil }
        self.recognizer = recognizer
    }

    /// Asks for speech-recognition and microphone permission (each prompt shows once).
    static func requestPermission() async -> Bool {
        guard await speechAuthorization() else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    /// The callback arrives on a background queue, so the closure must not be main-actor isolated.
    private nonisolated static func speechAuthorization() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in continuation.resume(returning: status == .authorized) }
        }
    }

    static var hasPermission: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
            && AVAudioApplication.shared.recordPermission == .granted
    }

    func listen(for seconds: Double, hints: [String]) async throws -> [String] {
        guard recognizer.isAvailable else { throw SpeechListenerError.unavailable }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .search
        request.contextualStrings = hints

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw SpeechListenerError.unavailable }
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tapBlock(appendingTo: request))

        let (events, continuation) = AsyncStream<RecognitionEvent>.makeStream()
        let task = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler(continuation))
        let state = ListenState()
        let consumer = Task { @MainActor [events, state] in
            for await event in events { state.apply(event) }
        }
        defer {
            engine.stop()
            input.removeTap(onBus: 0)
            task.cancel()
            continuation.finish()
            consumer.cancel()
        }

        engine.prepare()
        try engine.start()

        let start = Date.now
        while !state.isFinal {
            try await Task.sleep(for: .milliseconds(100))
            let elapsed = Date.now.timeIntervalSince(start)
            if state.latest.isEmpty {
                if elapsed >= seconds { break }
            } else if Date.now.timeIntervalSince(state.lastChange) >= Self.endOfSpeechSilence
                        || elapsed >= seconds + Self.overrun {
                break
            }
        }
        // Let the recogniser finish the last words.
        request.endAudio()
        engine.stop()
        let finishBy = Date.now.addingTimeInterval(0.8)
        while !state.isFinal, Date.now < finishBy {
            try await Task.sleep(for: .milliseconds(50))
        }
        return state.latest
    }

    // MARK: Callbacks off the main actor

    enum RecognitionEvent: Sendable {
        case heard([String], isFinal: Bool)
        case ended
    }

    @MainActor
    final class ListenState {
        var latest: [String] = []
        var lastChange = Date.now
        var isFinal = false

        func apply(_ event: RecognitionEvent) {
            switch event {
            case .heard(let transcriptions, let final):
                if transcriptions != latest {
                    latest = transcriptions
                    lastChange = .now
                }
                isFinal = isFinal || final
            case .ended:
                isFinal = true
            }
        }
    }

    // These run on audio and recogniser threads, so they're built outside the main actor.
    private nonisolated static func tapBlock(appendingTo request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        { buffer, _ in request.append(buffer) }
    }

    private nonisolated static func resultHandler(
        _ continuation: AsyncStream<RecognitionEvent>.Continuation
    ) -> @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        { result, error in
            if let result {
                let texts = result.transcriptions.map(\.formattedString).filter { !$0.isEmpty }
                continuation.yield(.heard(texts, isFinal: result.isFinal))
            }
            if error != nil { continuation.yield(.ended) }
        }
    }
}

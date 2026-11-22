import AVFoundation
import Speech

/// Listens for one spoken reply (ADR-0018). Recognition runs on the device only (ADR-0004):
/// nothing is recorded, stored or sent anywhere.
@MainActor
protocol SpeechListening: AnyObject {
    /// Listens for a fixed `seconds` (the think time). It stops early only when what's been
    /// heard `isConclusive` (an answer or a command) and the speaker has paused for about
    /// 1.2 s. Chatter, echo and mumbles keep it listening. Returns every alternative
    /// transcription, best first, or [] for silence. Throws when the microphone or the
    /// recogniser can't be used at all. Cancelling the calling task stops listening at once.
    func listen(for seconds: Double, hints: [String],
                isConclusive: @escaping @MainActor ([String]) -> Bool) async throws -> [String]
    /// Turns the mic on for a whole game, while the app is on screen (ADR-0028): iOS won't let
    /// it start in the background, only keep running. Without this, each `listen` turns the
    /// mic on and off again.
    func startMic() throws
    /// Turns the mic off at the end of the game.
    func stopMic()
}

extension SpeechListening {
    func startMic() throws {}
    func stopMic() {}
}

enum SpeechListenerError: Error, LocalizedError {
    case unavailable(String)
    /// Apple's speech recognition needs Dictation (or Siri) to be on (kLSRErrorDomain 201).
    case dictationOff
    /// The microphone couldn't start (in use by a call or another app, or no input).
    case micBusy(String)
    /// The on-device speech model is downloading (one time).
    case preparing

    static let dictationOffHelp = "Dictation is turned off on this iPhone, and spoken answers need it. "
        + "Turn it on in Settings → General → Keyboard → Enable Dictation. Siri can stay off."

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): reason
        case .dictationOff: "Siri and Dictation are disabled [kLSRErrorDomain 201]"
        case .micBusy(let detail): "The microphone didn't start. \(detail)"
        case .preparing: "Getting speech recognition ready (a one-time download)."
        }
    }

    /// "Siri and Dictation are disabled": kLSRErrorDomain 201, or kAFAssistantErrorDomain 1700
    /// on older systems.
    static func isDictationOff(domain: String, code: Int) -> Bool {
        (domain == "kLSRErrorDomain" && code == 201) || (domain == "kAFAssistantErrorDomain" && code == 1700)
    }
}

/// `SFSpeechRecognizer` on an `AVAudioEngine` input tap.
@MainActor
final class SystemSpeechListener: SpeechListening {
    /// How long a pause ends an answer.
    static let endOfSpeechSilence = 1.2
    /// Extra time allowed to finish an answer that started near the end of the window.
    static let overrun = 4.0

    /// Why listening last failed, shown in Mic check so a parent can tell us.
    private(set) static var lastProblem: String?

    /// Anonymous error reports (ADR-0020): which recognisers fail on which devices.
    weak var telemetry: (any TelemetryRecording)?

    /// Every English recogniser that can run on the device, best first. One that fails is
    /// moved to the back, so the next turn starts with one that works.
    private var recognizers: [SFSpeechRecognizer]

    /// nil when on-device recognition isn't available (we never fall back to Apple's servers).
    init?(preferredLocales: [Locale] = SystemSpeechListener.defaultLocales) {
        var seen = Set<String>()
        recognizers = preferredLocales
            .compactMap { SFSpeechRecognizer(locale: $0) }
            .filter { $0.supportsOnDeviceRecognition && seen.insert($0.locale.identifier).inserted }
        guard !recognizers.isEmpty else {
            Self.lastProblem = "This iPhone has no on-device English speech recognition."
            return nil
        }
    }

    static var defaultLocales: [Locale] {
        var locales = [Locale.current, Locale(identifier: "en-AU")]
        locales += ["en-US", "en-GB", "en-NZ", "en-IE", "en-CA", "en-IN", "en-ZA"].map(Locale.init(identifier:))
        return locales.filter { $0.language.languageCode?.identifier == "en" }
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

    /// iOS 26's SpeechAnalyzer, used once SFSpeechRecognizer has said Dictation is off.
    private var analyzer: AnyObject?
    private var analyzerFailed = false

    private let mic = MicInput()
    /// A game is on: the mic stays on between answers.
    private var keepMicOn = false

    func startMic() throws {
        do {
            try mic.start()
        } catch {
            Self.lastProblem = error.localizedDescription
            throw error
        }
        keepMicOn = true
    }

    func stopMic() {
        keepMicOn = false
        mic.stop()
    }

    func listen(for seconds: Double, hints: [String],
                isConclusive: @escaping @MainActor ([String]) -> Bool) async throws -> [String] {
        let end = Date.now.addingTimeInterval(seconds)
        // Already running during a game. Otherwise (Mic check) on for this listen only.
        do {
            try mic.start()
        } catch {
            Self.lastProblem = error.localizedDescription
            throw error
        }
        defer {
            mic.send(to: nil)
            if !keepMicOn { mic.stop() }
        }
        if #available(iOS 26.0, *), let analyzer = analyzer as? SpeechAnalyzerListener {
            return try await listen(with: analyzer, until: end, isConclusive: isConclusive)
        }
        do {
            return try await listenWithRecognizer(until: end, hints: hints, isConclusive: isConclusive)
        } catch SpeechListenerError.dictationOff {
            // Siri and Dictation are off. iOS 26 has a newer on-device recogniser that may still work.
            guard #available(iOS 26.0, *), !analyzerFailed else { throw SpeechListenerError.dictationOff }
            let analyzer = SpeechAnalyzerListener()
            self.analyzer = analyzer
            telemetry?.record("voice.trySpeechAnalyzer", [:])
            return try await listen(with: analyzer, until: end, isConclusive: isConclusive)
        }
    }

    @available(iOS 26.0, *)
    private func listen(with analyzer: SpeechAnalyzerListener, until end: Date,
                        isConclusive: @escaping @MainActor ([String]) -> Bool) async throws -> [String] {
        do {
            let heard = try await analyzer.listen(until: end, locales: Self.defaultLocales, mic: mic,
                                                  isConclusive: isConclusive)
            Self.lastProblem = nil
            return heard
        } catch is CancellationError {
            throw CancellationError()
        } catch SpeechAnalyzerListener.Problem.downloading {
            // The model is on its way (keep this analyzer so the download isn't started twice).
            Self.lastProblem = SpeechAnalyzerListener.Problem.downloading.localizedDescription
            throw SpeechListenerError.preparing
        } catch {
            telemetry?.record("voice.speechAnalyzerFailed", ["error": error.localizedDescription,
                                                             "type": String(describing: type(of: error))])
            analyzerFailed = true
            self.analyzer = nil
            Self.lastProblem = SpeechListenerError.dictationOffHelp
            throw SpeechListenerError.dictationOff
        }
    }

    private func listenWithRecognizer(until end: Date, hints: [String],
                                      isConclusive: @escaping @MainActor ([String]) -> Bool) async throws -> [String] {
        let feed = AudioFeed()
        mic.send(to: feed)
        defer {
            mic.send(to: nil)
            feed.set(nil)
        }

        var problems: [String] = []
        var dictationOff = 0
        var attempts = 0
        var lastHeard: [String] = []
        // Recognition can end before the window does (an error, or a final result). Start it
        // again so the child still gets the whole think time.
        while Date.now < end, attempts < recognizers.count + 5 {
            attempts += 1
            let recognizer = recognizers[0]
            let passStart = Date.now
            let pass = try await recognise(with: recognizer, feed: feed, hints: hints, until: end,
                                           isConclusive: isConclusive)
            if !pass.endedEarly || isConclusive(pass.heard) {
                Self.lastProblem = nil
                return pass.heard
            }
            lastHeard = pass.heard
            // Ending at once with nothing heard means this recogniser doesn't work (for example
            // its on-device model isn't installed): try the next one. Ending later is just a
            // quiet car, so keep listening with the same one.
            if pass.heard.isEmpty, Date.now.timeIntervalSince(passStart) < 2 {
                problems.append("\(recognizer.locale.identifier): \(pass.problem ?? "recognition stopped")")
                if pass.dictationOff { dictationOff += 1 }
                telemetry?.record("voice.recognizerFailed", [
                    "locale": recognizer.locale.identifier, "error": pass.problem ?? "recognition stopped",
                ])
                recognizers.append(recognizers.removeFirst())
            }
        }
        if !problems.isEmpty, problems.count == attempts {
            if dictationOff == problems.count {
                Self.lastProblem = SpeechListenerError.dictationOffHelp
                throw SpeechListenerError.dictationOff
            }
            throw fail("Speech recognition stopped straight away (\(problems.joined(separator: "; "))).")
        }
        return lastHeard
    }

    private func fail(_ reason: String) -> SpeechListenerError {
        Self.lastProblem = reason
        return .unavailable(reason)
    }

    private struct Pass {
        var heard: [String]
        /// Recognition ended by itself before the window closed.
        var endedEarly: Bool
        var problem: String?
        var dictationOff = false
    }

    private func recognise(
        with recognizer: SFSpeechRecognizer, feed: AudioFeed, hints: [String],
        until end: Date, isConclusive: @escaping @MainActor ([String]) -> Bool
    ) async throws -> Pass {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .search
        request.contextualStrings = hints

        let (events, continuation) = AsyncStream<RecognitionEvent>.makeStream()
        let task = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler(continuation))
        feed.set(request)
        let state = ListenState()
        let consumer = Task { @MainActor [events, state] in
            for await event in events { state.apply(event) }
        }
        defer {
            feed.set(nil)
            task.cancel()
            continuation.finish()
            consumer.cancel()
        }

        while !state.isFinal {
            try await Task.sleep(for: .milliseconds(100))
            let pausedAfterSpeech = !state.latest.isEmpty
                && Date.now.timeIntervalSince(state.lastChange) >= Self.endOfSpeechSilence
            if pausedAfterSpeech, isConclusive(state.latest) { break }
            if Date.now >= end {
                // Let a child who's mid-answer finish.
                let speaking = !state.latest.isEmpty && !pausedAfterSpeech
                if !speaking || Date.now >= end.addingTimeInterval(Self.overrun) { break }
            }
        }
        if state.isFinal {
            return Pass(heard: state.latest, endedEarly: Date.now < end, problem: state.problem,
                        dictationOff: state.dictationOff)
        }
        // Let the recogniser finish the last words.
        feed.set(nil)
        request.endAudio()
        let finishBy = Date.now.addingTimeInterval(0.8)
        while !state.isFinal, Date.now < finishBy {
            try await Task.sleep(for: .milliseconds(50))
        }
        return Pass(heard: state.latest, endedEarly: false, problem: nil)
    }

    // MARK: Callbacks off the main actor

    enum RecognitionEvent: Sendable {
        case heard([String], isFinal: Bool)
        case ended(String, dictationOff: Bool)
    }

    @MainActor
    final class ListenState {
        var latest: [String] = []
        var lastChange = Date.now
        var isFinal = false
        var problem: String?
        var dictationOff = false

        func apply(_ event: RecognitionEvent) {
            switch event {
            case .heard(let transcriptions, let final):
                if transcriptions != latest {
                    latest = transcriptions
                    lastChange = .now
                }
                isFinal = isFinal || final
            case .ended(let reason, let off):
                problem = reason
                dictationOff = off
                isFinal = true
            }
        }
    }

    /// Hands the mic's audio to whichever recognition request is current.
    final class AudioFeed: MicConsumer, @unchecked Sendable {
        private let lock = NSLock()
        private var request: SFSpeechAudioBufferRecognitionRequest?

        func set(_ request: SFSpeechAudioBufferRecognitionRequest?) {
            lock.withLock { self.request = request }
        }

        func append(_ buffer: AVAudioPCMBuffer) {
            lock.withLock { request }?.append(buffer)
        }
    }

    // This runs on a recogniser thread, so it's built outside the main actor.
    private nonisolated static func resultHandler(
        _ continuation: AsyncStream<RecognitionEvent>.Continuation
    ) -> @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        { result, error in
            if let result {
                let texts = result.transcriptions.map(\.formattedString).filter { !$0.isEmpty }
                continuation.yield(.heard(texts, isFinal: result.isFinal))
            }
            if let error {
                let ns = error as NSError
                continuation.yield(.ended("\(ns.localizedDescription) [\(ns.domain) \(ns.code)]",
                                          dictationOff: SpeechListenerError.isDictationOff(domain: ns.domain, code: ns.code)))
            }
        }
    }
}

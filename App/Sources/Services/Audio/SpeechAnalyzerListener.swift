import AVFoundation
import Speech

/// iOS 26's on-device `SpeechAnalyzer` + `SpeechTranscriber` (ADR-0018). Used when the older
/// `SFSpeechRecognizer` refuses to run because Siri and Dictation are off. Nothing leaves the
/// device. The English model is downloaded once by the system if it isn't installed yet; until
/// then this throws, and the game reads answers out.
@available(iOS 26.0, *)
@MainActor
final class SpeechAnalyzerListener {
    private var locale: Locale?
    private var download: Task<Void, Error>?

    enum Problem: Error, LocalizedError {
        case notSupported
        case downloading
        case noInput
        var errorDescription: String? {
            switch self {
            case .notSupported: "The new on-device speech recogniser isn't available for English on this iPhone."
            case .downloading: "Getting speech recognition ready (a one-time download). Try again in a minute."
            case .noInput: "No microphone input is available."
            }
        }
    }

    /// An English locale the transcriber supports, with its model installed. Starts the one-time
    /// download in the background and throws `.downloading` if it isn't installed yet.
    func prepare(locales: [Locale]) async throws -> Locale {
        if let locale { return locale }
        var chosen: Locale?
        for candidate in locales {
            if let supported = await SpeechTranscriber.supportedLocale(equivalentTo: candidate) {
                chosen = supported
                break
            }
        }
        guard let chosen else { throw Problem.notSupported }
        let transcriber = Self.makeTranscriber(chosen)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            if download == nil {
                download = Task { try await request.downloadAndInstall() }
            }
            throw Problem.downloading
        }
        locale = chosen
        return chosen
    }

    private static func makeTranscriber(_ locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults],
                          attributeOptions: [])
    }

    /// Same contract as `SpeechListening.listen`.
    func listen(for seconds: Double, locales: [Locale], isConclusive: ([String]) -> Bool) async throws -> [String] {
        let locale = try await prepare(locales: locales)
        let transcriber = Self.makeTranscriber(locale)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw Problem.notSupported
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw Problem.noInput }

        let (inputs, builder) = AsyncStream<AnalyzerInput>.makeStream()
        let feeder = AnalyzerFeeder(from: inputFormat, to: analyzerFormat, builder: builder)
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat, block: Self.tapBlock(feeding: feeder))

        let state = TranscriptState()
        let consumer = Task { @MainActor [transcriber, state] in
            do {
                for try await result in transcriber.results {
                    state.add(String(result.text.characters), isFinal: result.isFinal)
                }
            } catch {
                state.ended = true
            }
        }
        defer {
            engine.stop()
            input.removeTap(onBus: 0)
            builder.finish()
            consumer.cancel()
        }

        try await analyzer.start(inputSequence: inputs)
        engine.prepare()
        try engine.start()

        let deadline = Date.now.addingTimeInterval(seconds)
        while !state.ended {
            try await Task.sleep(for: .milliseconds(100))
            let heard = state.text.isEmpty ? [] : [state.text]
            let paused = !heard.isEmpty
                && Date.now.timeIntervalSince(state.lastChange) >= SystemSpeechListener.endOfSpeechSilence
            if paused, isConclusive(heard) { break }
            if Date.now >= deadline {
                let speaking = !heard.isEmpty && !paused
                if !speaking || Date.now >= deadline.addingTimeInterval(SystemSpeechListener.overrun) { break }
            }
        }
        engine.stop()
        builder.finish()
        let finishBy = Date.now.addingTimeInterval(0.8)
        let wrapUp = Task { try? await analyzer.finalizeAndFinishThroughEndOfInput() }
        while state.hasVolatile, Date.now < finishBy {
            try await Task.sleep(for: .milliseconds(50))
        }
        wrapUp.cancel()
        await analyzer.cancelAndFinishNow()
        return state.text.isEmpty ? [] : [state.text]
    }

    @MainActor
    final class TranscriptState {
        private var finalized = ""
        private var volatile = ""
        var lastChange = Date.now
        var ended = false

        var text: String { (finalized + " " + volatile).trimmingCharacters(in: .whitespaces) }
        var hasVolatile: Bool { !volatile.isEmpty }

        func add(_ text: String, isFinal: Bool) {
            if isFinal {
                finalized += " " + text
                volatile = ""
            } else {
                volatile = text
            }
            lastChange = .now
        }
    }

    /// Converts microphone audio to the analyzer's format on the audio thread.
    final class AnalyzerFeeder: @unchecked Sendable {
        private let converter: AVAudioConverter?
        private let format: AVAudioFormat
        private let builder: AsyncStream<AnalyzerInput>.Continuation

        init(from source: AVAudioFormat, to target: AVAudioFormat, builder: AsyncStream<AnalyzerInput>.Continuation) {
            converter = source == target ? nil : AVAudioConverter(from: source, to: target)
            format = target
            self.builder = builder
        }

        func feed(_ buffer: AVAudioPCMBuffer) {
            guard let converter else {
                builder.yield(AnalyzerInput(buffer: buffer))
                return
            }
            let ratio = format.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
            guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
            var supplied = false
            var error: NSError?
            let status = converter.convert(to: converted, error: &error) { _, inputStatus in
                if supplied {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                supplied = true
                inputStatus.pointee = .haveData
                return buffer
            }
            if status != .error, converted.frameLength > 0 {
                builder.yield(AnalyzerInput(buffer: converted))
            }
        }
    }

    private nonisolated static func tapBlock(feeding feeder: AnalyzerFeeder) -> AVAudioNodeTapBlock {
        { buffer, _ in feeder.feed(buffer) }
    }
}

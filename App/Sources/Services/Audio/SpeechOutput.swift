import AVFoundation

/// Speaks text aloud. `speak` returns when the utterance finishes and throws
/// `CancellationError` if the calling task is cancelled (pause/skip).
@MainActor
protocol SpeechOutput: AnyObject {
    func speak(_ text: String) async throws
    func stop()
}

/// Voice and rate chosen in Settings (FEATURES §2.5).
struct VoiceSettings: Equatable, Sendable {
    /// `AVSpeechSynthesisVoice.identifier`; nil means the best `en-AU` voice.
    var identifier: String?
    /// 0...1, mapped onto AVSpeechUtterance's rate range. Slightly slow by default for kids.
    var rate: Float = 0.45

    static let languages = ["en-AU", "en-GB", "en-US"]
}

/// On-device text-to-speech with `AVSpeechSynthesizer` (ADR-0008). No network.
@MainActor
final class SystemSpeechOutput: NSObject, SpeechOutput {
    private let synthesizer = AVSpeechSynthesizer()
    private var pending: (id: ObjectIdentifier, continuation: CheckedContinuation<Void, Never>)?
    var voiceSettings: @MainActor () -> VoiceSettings

    init(voiceSettings: @escaping @MainActor () -> VoiceSettings) {
        self.voiceSettings = voiceSettings
        super.init()
        synthesizer.delegate = self
        // We manage the audio session ourselves (AudioSessionController).
        synthesizer.usesApplicationAudioSession = true
    }

    func speak(_ text: String) async throws {
        try Task.checkCancellation()
        let utterance = AVSpeechUtterance(string: text)
        let settings = voiceSettings()
        utterance.voice = Self.voice(for: settings.identifier)
        let range = AVSpeechUtteranceMaximumSpeechRate - AVSpeechUtteranceMinimumSpeechRate
        utterance.rate = AVSpeechUtteranceMinimumSpeechRate + range * settings.rate
        utterance.postUtteranceDelay = 0.15
        let id = ObjectIdentifier(utterance)

        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                finishPending()
                pending = (id, continuation)
                synthesizer.speak(utterance)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.stop() }
        }
        try Task.checkCancellation()
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        finishPending()
    }

    private func finishPending(matching id: ObjectIdentifier? = nil) {
        guard let pending, id == nil || pending.id == id else { return }
        self.pending = nil
        pending.continuation.resume()
    }

    static func voice(for identifier: String?) -> AVSpeechSynthesisVoice? {
        if let identifier, let voice = AVSpeechSynthesisVoice(identifier: identifier) { return voice }
        return availableVoices().first { $0.language == "en-AU" } ?? AVSpeechSynthesisVoice(language: "en-AU")
    }

    /// English voices offered in Settings, best quality first.
    static func availableVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { VoiceSettings.languages.contains($0.language) }
            .sorted {
                if $0.language != $1.language {
                    return VoiceSettings.languages.firstIndex(of: $0.language)! < VoiceSettings.languages.firstIndex(of: $1.language)!
                }
                if $0.quality != $1.quality { return $0.quality.rawValue > $1.quality.rawValue }
                return $0.name < $1.name
            }
    }
}

extension SystemSpeechOutput: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.finishPending(matching: id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.finishPending(matching: id) }
    }
}

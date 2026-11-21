import Foundation

/// Known problems mapped to a short fix: "Settings › General › Keyboard › Enable Dictation".
/// Anything not in the map is shown as the error itself.
struct FixGuide: Equatable, Sendable {
    /// A few words: "Dictation is off".
    let problem: String
    /// Where to go, step by step.
    let steps: [String]
    /// Show an "Open Settings" button (the Settings app, at BuckleUp Quiz's page).
    var opensSettings = true

    var path: String { steps.joined(separator: " › ") }

    static let dictationOff = FixGuide(
        problem: "Dictation is off",
        steps: ["Settings", "General", "Keyboard", "Enable Dictation"])

    static let permissionOff = FixGuide(
        problem: "Microphone or speech access is off",
        steps: ["Settings", "Apps", "BuckleUp Quiz", "Microphone + Speech Recognition"])

    static let micBusy = FixGuide(
        problem: "The microphone is busy",
        steps: ["End any call or recording", "Close other apps using the mic", "Try again"],
        opensSettings: false)

    static let preparing = FixGuide(
        problem: "Getting speech ready (one-time download)",
        steps: ["Stay on Wi-Fi", "Try again in a minute"],
        opensSettings: false)

    static let noOnDeviceSpeech = FixGuide(
        problem: "No offline English speech on this iPhone",
        steps: ["Settings", "General", "Keyboard", "Enable Dictation", "Dictation Languages: English"])

    /// The guide for an error, or nil to show the error as it is.
    static func guide(for error: any Error) -> FixGuide? {
        switch error {
        case SpeechListenerError.dictationOff: return .dictationOff
        case SpeechListenerError.micBusy: return .micBusy
        case SpeechListenerError.preparing: return .preparing
        default: break
        }
        let ns = error as NSError
        if SpeechListenerError.isDictationOff(domain: ns.domain, code: ns.code) { return .dictationOff }
        return nil
    }
}

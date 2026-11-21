/// Spoken game controls (FEATURES §3.3). Only short, exact phrases count,
/// so a real answer is never mistaken for a command.
public enum VoiceCommand: String, CaseIterable, Sendable {
    case skip, `repeat`, pause, stop

    private static let phrases: [String: VoiceCommand] = [
        "skip": .skip, "next": .skip, "skip it": .skip, "next one": .skip, "next question": .skip,
        "pass": .skip, "skip please": .skip, "next please": .skip,
        "repeat": .repeat, "say again": .repeat, "say it again": .repeat, "again": .repeat,
        "repeat please": .repeat, "repeat that": .repeat, "what": .repeat, "pardon": .repeat,
        "pause": .pause, "wait": .pause, "pause please": .pause, "hold on": .pause,
        "stop": .stop, "stop game": .stop, "end game": .stop, "quit": .stop, "stop please": .stop,
    ]

    /// The command in any of the transcriptions, if one is an exact command phrase.
    public static func parse(_ transcriptions: [String]) -> VoiceCommand? {
        for t in transcriptions {
            if let command = phrases[TextNormalizer.tokens(t).joined(separator: " ")] { return command }
        }
        return nil
    }
}

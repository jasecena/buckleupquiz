import Foundation
@testable import BuckleUpQuiz
import QuizCore

@MainActor
final class FakeSpeech: SpeechOutput {
    private(set) var spoken: [String] = []
    /// Pauses on the first line this matches until `release()`, so a test can act at an exact
    /// moment instead of racing the runner with `Task.yield()`.
    var holdWhen: (@MainActor (String) -> Bool)?
    private var held: CheckedContinuation<Void, Never>?
    var isHolding: Bool { held != nil }

    func speak(_ text: String) async throws {
        try Task.checkCancellation()
        spoken.append(text)
        if let holdWhen, holdWhen(text) {
            self.holdWhen = nil
            await withCheckedContinuation { held = $0 }
        }
        await Task.yield()
        try Task.checkCancellation()
    }

    func release() {
        held?.resume()
        held = nil
    }

    func stop() {}
}

@MainActor
final class FakeCues: CuePlaying {
    private(set) var events: [String] = []
    func startSession() { events.append("start") }
    func endSession() { events.append("end") }
    func startThinking() { events.append("think") }
    func stopThinking() { events.append("stopThink") }
    func play(_ cue: CueSound) { events.append("cue") }
}

@MainActor
final class FakeAudioSession: AudioSessionControlling {
    var onEvent: ((AudioSessionEvent) -> Void)?
    private(set) var active = false
    private(set) var voice = false
    func activateForListening(duckOthers: Bool) throws { active = true }
    func activateForVoice(duckOthers: Bool, mic: MicPreference) throws -> String? {
        active = true
        voice = true
        return "Test Car"
    }
    func deactivate() { active = false }
}

/// Replies with scripted transcriptions, one per `listen` call ([] = silence).
/// `FakeListener.rightLetter` and `.wrongLetter` stand for the letter of the right (or a wrong)
/// option of whatever is being asked, since options are shuffled.
@MainActor
final class FakeListener: SpeechListening {
    static let rightLetter = "<right letter>"
    static let wrongLetter = "<wrong letter>"

    var replies: [[String]]
    var failure: (any Error)?
    /// The failure happens on the first listen only.
    var failsOnce: Bool
    private(set) var listens = 0
    /// Whether the game has the mic on (`startMic` … `stopMic`).
    private(set) var micOn = false
    private(set) var micStarts = 0

    init(_ replies: [[String]], failure: (any Error)? = nil, failsOnce: Bool = false) {
        self.replies = replies
        self.failure = failure
        self.failsOnce = failsOnce
    }

    func startMic() throws {
        micOn = true
        micStarts += 1
    }

    func stopMic() { micOn = false }

    func listen(for seconds: Double, hints: [String],
                isConclusive: @escaping @MainActor ([String]) -> Bool) async throws -> [String] {
        listens += 1
        await Task.yield()
        try Task.checkCancellation()
        if let failure {
            if failsOnce { self.failure = nil }
            throw failure
        }
        return replies.isEmpty ? [] : replies.removeFirst().map(resolve)
    }

    /// The question being asked, so `rightLetter` / `wrongLetter` can be turned into a letter.
    var asking: (@MainActor () -> PresentedQuestion?)?

    private func resolve(_ text: String) -> String {
        guard let presented = asking?(), let right = presented.correctOptionIndex else { return text }
        let letters = presented.optionLetters
        return text
            .replacingOccurrences(of: Self.rightLetter, with: letters[right])
            .replacingOccurrences(of: Self.wrongLetter, with: letters[(right + 1) % letters.count])
    }
}

struct InstantSleeper: Sleeper {
    func sleep(seconds: Double) async throws {
        await Task.yield()
        try Task.checkCancellation()
    }
}

/// `count` questions for ages 6–8, plus `olderCount` for ages 11–12.
func makeBank(questions count: Int, olderCount: Int = 0) -> QuestionBank {
    func band(_ i: Int) -> AgeBand { i < count ? .sixToEight : .elevenToTwelve }
    let topic = Topic(id: "animals", name: "Animals", symbol: "pawprint", color: "#F39C12",
                      category: .knowledge, isFree: true)
    let questions = (0..<(count + olderCount)).map { i in
        Question(id: "ani-\(1000 + i)", topic: "animals", ageBand: band(i), type: .multipleChoice,
                 question: "Question \(i)?", options: ["Answer \(i)", "Other", "Another"], answer: "Answer \(i)")
    }
    return QuestionBank(topics: [topic], questions: questions)
}

@MainActor
final class FakeTelemetry: TelemetryRecording {
    private(set) var events: [(name: String, fields: [String: String])] = []
    func record(_ name: String, _ fields: [String: String]) { events.append((name, fields)) }
    var names: [String] { events.map(\.name) }
}

import Foundation
@testable import BuckleUpQuiz
import QuizCore

@MainActor
final class FakeSpeech: SpeechOutput {
    private(set) var spoken: [String] = []

    func speak(_ text: String) async throws {
        try Task.checkCancellation()
        spoken.append(text)
        await Task.yield()
        try Task.checkCancellation()
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
@MainActor
final class FakeListener: SpeechListening {
    var replies: [[String]]
    var failure: (any Error)?
    private(set) var listens = 0

    init(_ replies: [[String]], failure: (any Error)? = nil) {
        self.replies = replies
        self.failure = failure
    }

    func listen(until deadline: @escaping @MainActor () -> Date, hints: [String],
                isConclusive: @escaping @MainActor ([String]) -> Bool) async throws -> [String] {
        listens += 1
        await Task.yield()
        try Task.checkCancellation()
        if let failure { throw failure }
        return replies.isEmpty ? [] : replies.removeFirst()
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

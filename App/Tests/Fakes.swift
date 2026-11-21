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
    func activateForListening(duckOthers: Bool) throws { active = true }
    func deactivate() { active = false }
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

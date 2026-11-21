@testable import BuckleUpQuiz
import QuizCore
import Testing

@MainActor
@Suite("Listen mode session")
struct ListenSessionModelTests {
    let speech = FakeSpeech()
    let cues = FakeCues()
    let audio = FakeAudioSession()

    func makeModel(questions: Int = 3, length: SessionLength = .questions(3)) -> ListenSessionModel {
        let config = SessionConfig(topics: ["animals"], players: [.listener(ageBand: .sixToEight)], length: length)
        var settings = ListenSettings()
        settings.thinkTime = 3
        return ListenSessionModel(
            bank: makeBank(questions: questions), config: config, settings: settings, duckOthers: true,
            dependencies: .init(speech: speech, cues: cues, sleeper: InstantSleeper(), audioSession: audio),
            rng: AnyRandomGenerator(seed: 1))
    }

    @Test func playsAWholeSessionWithNoTaps() async {
        let model = makeModel()
        model.start()
        #expect(audio.active)
        await model.runner?.value

        #expect(model.status == .finished)
        #expect(speech.spoken.first == Phrases.intro)
        #expect(speech.spoken.filter { $0.hasPrefix("The answer is") }.count == 3)
        #expect(speech.spoken.last == "That's the end of the ride! Great listening, everyone!")
        #expect(cues.events.first == "start")
        #expect(cues.events.last == "end")
        #expect(cues.events.filter { $0 == "think" }.count == 3)
        #expect(!audio.active, "audio session is released at the end")
    }

    @Test func stopEndsImmediately() {
        let model = makeModel()
        model.start()
        model.stop()
        #expect(model.status == .finished)
        #expect(cues.events.last == "end")
    }

    @Test func phoneCallPausesThenWelcomesBack() async {
        let model = makeModel()
        model.start()
        model.handle(.interruptionBegan)
        #expect(model.status == .paused)

        model.handle(.interruptionEnded(shouldResume: true))
        #expect(model.status == .playing)
        await model.runner?.value

        #expect(speech.spoken.first == Phrases.welcomeBack)
        #expect(model.status == .finished)
    }

    @Test func remoteCommandsControlPlayback() {
        let model = makeModel()
        model.start()
        model.handle(RemoteCommand.pause)
        #expect(model.status == .paused)
        model.handle(RemoteCommand.toggle)
        #expect(model.status == .playing)
        model.stop()
    }

    @Test func namedPlayersTakeTurnsWithTheirOwnAgeQuestions() async {
        let mia = Player(id: "mia", name: "Mia", age: 7)
        let leo = Player(id: "leo", name: "Leo", age: 11)
        let config = SessionConfig(topics: ["animals"], players: [mia, leo], length: .questions(4))
        var seen: [String: Set<String>] = [:]
        let model = ListenSessionModel(
            bank: makeBank(questions: 3, olderCount: 3), config: config, settings: ListenSettings(), duckOthers: true,
            dependencies: .init(speech: speech, cues: cues, sleeper: InstantSleeper(), audioSession: audio),
            rng: AnyRandomGenerator(seed: 2))
        model.onFinish = { seen = $0 }
        model.start()
        await model.runner?.value

        let addressed = speech.spoken.filter { $0.contains("this one's for you") }
        #expect(addressed.count == 4)
        #expect(addressed[0].hasPrefix("Mia,"))
        #expect(addressed[1].hasPrefix("Leo,"))
        #expect(speech.spoken.last == "That's the end of the ride! Great job, Mia and Leo!")
        #expect(seen["mia"]?.count == 2)
        #expect(seen["leo"]?.count == 2)
        // Mia (7) only heard 6–8 questions; Leo (11) only 11–12 ones (ids ani-1003…).
        #expect(seen["mia"]?.allSatisfy { ["ani-1000", "ani-1001", "ani-1002"].contains($0) } == true)
        #expect(seen["leo"]?.allSatisfy { ["ani-1003", "ani-1004", "ani-1005"].contains($0) } == true)
    }

    @Test func endsEarlyWhenQuestionsRunOut() async {
        let model = makeModel(questions: 2, length: .questions(10))
        model.start()
        await model.runner?.value
        #expect(model.status == .finished)
        #expect(speech.spoken.filter { $0.hasPrefix("The answer is") }.count == 2)
    }
}

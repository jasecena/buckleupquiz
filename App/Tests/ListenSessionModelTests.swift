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

    @Test func endsEarlyWhenQuestionsRunOut() async {
        let model = makeModel(questions: 2, length: .questions(10))
        model.start()
        await model.runner?.value
        #expect(model.status == .finished)
        #expect(speech.spoken.filter { $0.hasPrefix("The answer is") }.count == 2)
    }
}

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
        var learned: [String: LearningRecord] = [:]
        let model = ListenSessionModel(
            bank: makeBank(questions: 3, olderCount: 3), config: config, settings: ListenSettings(), duckOthers: true,
            dependencies: .init(speech: speech, cues: cues, sleeper: InstantSleeper(), audioSession: audio),
            rng: AnyRandomGenerator(seed: 2))
        model.onFinish = { learned = $0 }
        model.start()
        await model.runner?.value

        let addressed = speech.spoken.filter { $0.contains("this one's for you") }
        #expect(addressed.count == 4)
        #expect(addressed[0].hasPrefix("Mia,"))
        #expect(addressed[1].hasPrefix("Leo,"))
        #expect(speech.spoken.last == "That's the end of the ride! Great job, Mia and Leo!")
        let miaCards = learned["mia"]?.cards ?? [:]
        let leoCards = learned["leo"]?.cards ?? [:]
        #expect(miaCards.count == 2)
        #expect(leoCards.count == 2)
        // Mia (7) only heard 6–8 questions; Leo (11) only 11–12 ones (ids ani-1003…).
        #expect(miaCards.keys.allSatisfy { ["ani-1000", "ani-1001", "ani-1002"].contains($0) })
        #expect(leoCards.keys.allSatisfy { ["ani-1003", "ani-1004", "ani-1005"].contains($0) })
        // Heard and not marked counts as right: back tomorrow (box 2).
        #expect(miaCards.values.allSatisfy { $0.box == 2 })
    }

    @Test func notYetSendsTheQuestionBackToBoxOne() async {
        let config = SessionConfig(topics: ["animals"], players: [Player(id: "mia", name: "Mia", age: 7)],
                                   length: .questions(1))
        var learned: [String: LearningRecord] = [:]
        let model = ListenSessionModel(
            bank: makeBank(questions: 1), config: config, settings: ListenSettings(), duckOthers: true,
            dependencies: .init(speech: speech, cues: cues, sleeper: InstantSleeper(), audioSession: audio),
            day: 40, rng: AnyRandomGenerator(seed: 1))
        model.onFinish = { learned = $0 }
        model.start()
        for _ in 0..<2000 where !model.canMark { await Task.yield() }
        #expect(model.canMark)
        #expect(model.result == .heard)
        model.mark(.incorrect)
        await model.runner?.value
        #expect(learned["mia"]?.card("ani-1000") == ReviewCard(box: 1, due: 40))
    }

    @Test func talkAboutWaitsUntilTheFamilyIsDone() async {
        let topic = Topic(id: "manners", name: "Manners", symbol: "heart", color: "#E74C3C",
                          category: .values, isFree: true)
        let prompt = Question(id: "man-1000", topic: "manners", ageBand: .sixToEight, type: .talkAbout,
                              question: "What made you smile today?", options: nil, answer: nil)
        let config = SessionConfig(topics: ["manners"], players: [.listener(ageBand: .sixToEight)],
                                   length: .questions(1), includeTalkAbout: true)
        let model = ListenSessionModel(
            bank: QuestionBank(topics: [topic], questions: [prompt]), config: config, settings: ListenSettings(),
            duckOthers: true, dependencies: .init(speech: speech, cues: cues, sleeper: InstantSleeper(), audioSession: audio),
            rng: AnyRandomGenerator(seed: 1))
        model.start()
        for _ in 0..<200 where !model.isDiscussing { await Task.yield() }

        #expect(model.isDiscussing, "no timer: it waits for the family")
        #expect(speech.spoken.last == Phrases.talkItOver)
        #expect(!cues.events.contains("think"), "no ticking while people talk")

        model.skip() // the car's next-track button
        await model.runner?.value
        #expect(!model.isDiscussing)
        #expect(speech.spoken.contains(Phrases.greatChat))
        #expect(model.status == .finished)
    }

    @Test func endsEarlyWhenQuestionsRunOut() async {
        let model = makeModel(questions: 2, length: .questions(10))
        model.start()
        await model.runner?.value
        #expect(model.status == .finished)
        #expect(speech.spoken.filter { $0.hasPrefix("The answer is") }.count == 2)
    }
}

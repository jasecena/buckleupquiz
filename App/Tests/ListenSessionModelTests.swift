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
        let config = SessionConfig(topics: ["animals"], players: [mia, leo], length: .questions(2))
        var learned: [String: LearningRecord] = [:]
        let model = ListenSessionModel(
            bank: makeBank(questions: 3, olderCount: 3), config: config, settings: ListenSettings(), duckOthers: true,
            dependencies: .init(speech: speech, cues: cues, sleeper: InstantSleeper(), audioSession: audio),
            rng: AnyRandomGenerator(seed: 2))
        model.onFinish = { learned = $0.learning }
        model.start()
        await model.runner?.value

        let addressed = speech.spoken.filter { $0.contains("this one's for you") }
        #expect(addressed == ["Mia, this one's for you!", "Leo, this one's for you!"], "only on each player's first turn")
        #expect(speech.spoken.filter { $0 == "Mia." || $0 == "Leo." } == ["Mia.", "Leo."])
        #expect(speech.spoken.last?.hasPrefix("That's the end of the ride! Great job, Mia and Leo!") == true)
        #expect(speech.spoken.last?.hasSuffix(Phrases.scoreFixNote) == true)
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
        model.onFinish = { learned = $0.learning }
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

    // MARK: Voice answers (ADR-0018)

    func makeVoiceModel(_ replies: [[String]], questions: Int = 1, length: Int = 1) -> (ListenSessionModel, FakeListener) {
        let listener = FakeListener(replies)
        let config = SessionConfig(topics: ["animals"], players: [Player(id: "mia", name: "Mia", age: 7)],
                                   length: .questions(length))
        let model = ListenSessionModel(
            bank: makeBank(questions: questions), config: config, settings: ListenSettings(), duckOthers: true,
            dependencies: .init(speech: speech, cues: cues, sleeper: InstantSleeper(), audioSession: audio,
                                listener: listener),
            answerMode: .voice, rng: AnyRandomGenerator(seed: 1))
        return (model, listener)
    }

    @Test func rightSpokenAnswerScoresForThePlayerWhoseTurnItIs() async {
        let (model, _) = makeVoiceModel([["I think it's answer 0"]])
        var summary: SessionSummary?
        model.onFinish = { summary = $0 }
        model.start()
        #expect(audio.voice)
        await model.runner?.value

        #expect(speech.spoken.contains(Phrases.voiceTip))
        #expect(speech.spoken.contains { $0.hasPrefix("Correct!") })
        #expect(model.scoreboard.first?.points == 10)
        #expect(speech.spoken.last?.contains("Mia got 10 points") == true)
        #expect(summary?.stats["mia"]?.correct == 1)
        #expect(summary?.learning["mia"]?.card("ani-1000")?.box == 2)
    }

    @Test func wrongAnswerJustSharesTheAnswerAndStartsOver() async {
        let (model, _) = makeVoiceModel([["another"]])
        var summary: SessionSummary?
        model.onFinish = { summary = $0 }
        model.start()
        await model.runner?.value
        #expect(speech.spoken.contains { $0.hasPrefix("The answer is") && $0.contains("Answer 0") })
        #expect(!speech.spoken.contains { $0.contains("Not quite") })
        #expect(model.scoreboard.first?.points == 0)
        #expect(summary?.learning["mia"]?.card("ani-1000")?.box == 1)
    }

    @Test func mumbleIsQuietlyLetGo() async {
        let (model, listener) = makeVoiceModel([["umm"]])
        var summary: SessionSummary?
        model.onFinish = { summary = $0 }
        model.start()
        await model.runner?.value
        #expect(listener.listens == 1, "no \"say it again\"")
        #expect(speech.spoken.contains { $0.hasPrefix("The answer is") })
        #expect(summary?.learning["mia"]?.card("ani-1000") == nil, "boxes untouched when not heard")
    }

    @Test func sayingSkipMovesOn() async {
        let (model, _) = makeVoiceModel([["skip"], ["next"]], questions: 2, length: 2)
        model.start()
        for _ in 0..<5000 where model.status != .finished { await Task.yield() }
        #expect(model.status == .finished)
        #expect(!speech.spoken.contains { $0.hasPrefix("Not quite") || $0.hasPrefix("Time's up") })
    }

    @Test func brokenMicStillWaitsTheThinkTimeAndIsReported() async {
        let listener = FakeListener([], failure: SpeechListenerError.unavailable("no input"))
        let telemetry = FakeTelemetry()
        let config = SessionConfig(topics: ["animals"], players: [Player(id: "mia", name: "Mia", age: 7)],
                                   length: .questions(1))
        let model = ListenSessionModel(
            bank: makeBank(questions: 1), config: config, settings: ListenSettings(), duckOthers: true,
            dependencies: .init(speech: speech, cues: cues, sleeper: InstantSleeper(), audioSession: audio,
                                telemetry: telemetry, listener: listener),
            answerMode: .voice, rng: AnyRandomGenerator(seed: 1))
        model.start()
        await model.runner?.value
        #expect(cues.events.contains("think"), "falls back to the think countdown instead of answering at once")
        #expect(speech.spoken.contains { $0.hasPrefix("The answer is") })
        #expect(!model.isVoice)
        #expect(telemetry.names == ["voice.listenFailed", "game.finished"])
        #expect(telemetry.events[0].fields["error"] == "no input")
        #expect(telemetry.events[1].fields["fellBackToListen"] == "true")
        let everything = telemetry.events.flatMap { $0.fields.values }.joined(separator: " ")
        #expect(!everything.contains("Mia"), "no names in reports")
    }

    @Test func skippingMidQuestionKeepsItTheSamePlayersTurn() async {
        let mia = Player(id: "mia", name: "Mia", age: 7)
        let leo = Player(id: "leo", name: "Leo", age: 11)
        let listener = FakeListener([["skip"], ["answer 1"], []])
        let model = ListenSessionModel(
            bank: makeBank(questions: 3, olderCount: 3), config: SessionConfig(topics: ["animals"], players: [mia, leo],
                                                                                length: .questions(1)),
            settings: ListenSettings(), duckOthers: true,
            dependencies: .init(speech: speech, cues: cues, sleeper: InstantSleeper(), audioSession: audio,
                                listener: listener),
            answerMode: .voice, rng: AnyRandomGenerator(seed: 2))
        model.start()
        for _ in 0..<20000 where model.status != .finished { await Task.yield() }
        #expect(model.status == .finished)
        let names = speech.spoken.filter { $0.hasPrefix("Mia") || $0.hasPrefix("Leo") }
        #expect(names == ["Mia, this one's for you!", "Mia.", "Leo, this one's for you!"])
        #expect(speech.spoken.filter { $0 == "Question two." }.count == 1, "the skip didn't use up a question")
        #expect(speech.spoken.filter { $0 == Phrases.intro }.count == 1)
        #expect(speech.spoken.contains(Phrases.anotherOne))
    }

    @Test func gotItScoresInListenModeAndTheScoreboardShowsFromTheStart() async {
        let mia = Player(id: "mia", name: "Mia", age: 7)
        let leo = Player(id: "leo", name: "Leo", age: 11)
        let model = ListenSessionModel(
            bank: makeBank(questions: 3, olderCount: 3), config: SessionConfig(topics: ["animals"], players: [mia, leo],
                                                                                length: .questions(1)),
            settings: ListenSettings(), duckOthers: true,
            dependencies: .init(speech: speech, cues: cues, sleeper: InstantSleeper(), audioSession: audio),
            rng: AnyRandomGenerator(seed: 2))
        #expect(model.showsScores, "named players see the scoreboard before anyone answers")
        model.start()
        for _ in 0..<20000 where !model.canMark { await Task.yield() }
        #expect(model.turn?.player.id == "mia")
        model.mark(.correct)
        #expect(model.scoreboard.first { $0.player.id == "mia" }?.points == 10, "shows straight away")
        await model.runner?.value
        #expect(model.scoreboard.first { $0.player.id == "mia" }?.points == 10)
        #expect(model.scoreboard.first { $0.player.id == "leo" }?.points == 0)
        #expect(model.showsFinalScores)
        #expect(speech.spoken.last?.contains("Mia got 10 points") == true || speech.spoken.last?.contains("Mia wins") == true)
        #expect(speech.spoken.last?.hasSuffix(Phrases.scoreFixNote) == true, "kids hear that scores can be fixed")

        // A grown-up fixes Leo's score: he did get his answer right.
        var adjusted: [(String, Int)] = []
        model.onScoreAdjusted = { adjusted.append(($0, $1)) }
        #expect(model.maxPoints(for: "leo") == 10)
        model.setPoints(50, for: "leo")
        #expect(model.scoreboard.first { $0.player.id == "leo" }?.points == 10, "capped at what one question allows")
        #expect(adjusted.count == 1 && adjusted[0].0 == "leo" && adjusted[0].1 == 10)
    }

    @Test func dictationOffGivesTheGrownUpsTheFix() async {
        let listener = FakeListener([], failure: SpeechListenerError.dictationOff)
        let model = ListenSessionModel(
            bank: makeBank(questions: 1), config: SessionConfig(topics: ["animals"],
                                                                players: [Player(id: "mia", name: "Mia", age: 7)],
                                                                length: .questions(1)),
            settings: ListenSettings(), duckOthers: true,
            dependencies: .init(speech: speech, cues: cues, sleeper: InstantSleeper(), audioSession: audio,
                                listener: listener),
            answerMode: .voice, rng: AnyRandomGenerator(seed: 1))
        model.start()
        await model.runner?.value
        #expect(model.voiceOffHint?.contains("Dictation") == true)
        #expect(!speech.spoken.contains { $0.contains("Dictation") }, "never said out loud to the kids")
        #expect(SpeechListenerError.isDictationOff(domain: "kLSRErrorDomain", code: 201))
    }

    @Test func scoreboardCanBeTurnedOff() async {
        let listener = FakeListener([["answer 0"]])
        let model = ListenSessionModel(
            bank: makeBank(questions: 1), config: SessionConfig(topics: ["animals"],
                                                                players: [Player(id: "mia", name: "Mia", age: 7)],
                                                                length: .questions(1)),
            settings: ListenSettings(), duckOthers: true,
            dependencies: .init(speech: speech, cues: cues, sleeper: InstantSleeper(), audioSession: audio,
                                listener: listener),
            answerMode: .voice, showScoreboard: false, rng: AnyRandomGenerator(seed: 1))
        #expect(!model.showsScores)
        model.start()
        await model.runner?.value
        #expect(speech.spoken.contains { $0.hasPrefix("Correct!") }, "still cheered")
        #expect(!model.showsFinalScores)
        #expect(speech.spoken.last?.hasPrefix("That's the end of the ride! Great job, Mia!") == true)
        #expect(!(speech.spoken.last ?? "").contains("points"))
    }

    @Test func silenceIsNeverMentioned() async {
        let (model, listener) = makeVoiceModel([], questions: 5, length: 5)
        model.start()
        await model.runner?.value
        #expect(listener.listens == 5, "keeps listening every turn, in case they join in")
        #expect(speech.spoken.filter { $0.hasPrefix("The answer is") }.count == 5)
        #expect(!speech.spoken.contains { $0.contains("Time's up") || $0.contains("hear") || $0.contains("0 points") })
        #expect(model.isVoice)
    }

    @Test func endsEarlyWhenQuestionsRunOut() async {
        let model = makeModel(questions: 2, length: .questions(10))
        model.start()
        await model.runner?.value
        #expect(model.status == .finished)
        #expect(speech.spoken.filter { $0.hasPrefix("The answer is") }.count == 2)
    }
}

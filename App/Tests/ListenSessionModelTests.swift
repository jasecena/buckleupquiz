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
        #expect(speech.spoken.last == "That's the end of the game! That was 3 questions. Great listening, everyone! "
                + Phrases.playAgain)
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
        #expect(speech.spoken.last?.hasPrefix("That's the end of the game! That was 2 questions each. Great job, Mia and Leo!") == true)
        #expect(speech.spoken.last?.contains(Phrases.scoreFixNote) == true)
        #expect(speech.spoken.last?.hasSuffix(Phrases.playAgain) == true, "the game is over, and another is a tap away")
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
        listener.asking = { [weak model] in model?.turn?.presented }
        return (model, listener)
    }

    @Test func rightSpokenAnswerScoresForThePlayerWhoseTurnItIs() async {
        let (model, _) = makeVoiceModel([["I think it's " + FakeListener.rightLetter]])
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
        let (model, _) = makeVoiceModel([[FakeListener.wrongLetter]])
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
        #expect(summary?.learning["mia"]?.card("ani-1000")?.box == 2, "not caught wrong counts as remembered")
        #expect(model.scoreboard.first?.points == 0, "but no points")
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

    @Test func varietyNeverDelaysTheStartOrTheEnd() async {
        let config = SessionConfig(topics: ["animals"], players: [.listener(ageBand: .sixToEight)], length: .questions(5))
        let model = ListenSessionModel(
            bank: makeBank(questions: 5), config: config, settings: ListenSettings(), duckOthers: true,
            dependencies: .init(speech: speech, cues: cues, sleeper: InstantSleeper(), audioSession: audio),
            variety: true, rng: AnyRandomGenerator(seed: 3))
        model.start()
        await model.runner?.value
        #expect(model.status == .finished)
        #expect(speech.spoken.first == Phrases.intro, "the first question starts straight away")
        #expect(speech.spoken.last?.hasPrefix(Phrases.outroPrefix) == true, "nothing between the last answer and the end")
        #expect(speech.spoken.filter { $0.hasPrefix("The answer is") }.count == 5)
    }

    @Test func theMicIsOnForTheWholeGameSoItWorksInTheBackground() async {
        let listener = FakeListener([[FakeListener.rightLetter]])
        let config = SessionConfig(topics: ["animals"], players: [Player(id: "mia", name: "Mia", age: 7)],
                                   length: .questions(1))
        let model = ListenSessionModel(
            bank: makeBank(questions: 1), config: config, settings: ListenSettings(), duckOthers: true,
            dependencies: .init(speech: speech, cues: cues, sleeper: InstantSleeper(), audioSession: audio,
                                listener: listener),
            answerMode: .voice, rng: AnyRandomGenerator(seed: 1))
        model.start()
        #expect(listener.micOn, "started on screen: iOS won't start the mic in the background")
        #expect(listener.micStarts == 1)
        await model.runner?.value
        #expect(model.status == .finished)
        #expect(!listener.micOn, "off when the game ends")
    }

    func makePausableVoiceModel(_ listener: FakeListener) -> ListenSessionModel {
        let config = SessionConfig(topics: ["animals"], players: [Player(id: "mia", name: "Mia", age: 7)],
                                   length: .questions(1))
        return ListenSessionModel(
            bank: makeBank(questions: 1), config: config, settings: ListenSettings(), duckOthers: true,
            dependencies: .init(speech: speech, cues: cues, sleeper: InstantSleeper(), audioSession: audio,
                                listener: listener),
            answerMode: .voice, rng: AnyRandomGenerator(seed: 1))
    }

    @Test func aForgottenPauseTurnsTheMicOffAndPlayTurnsItBackOn() async {
        let listener = FakeListener([])
        let model = makePausableVoiceModel(listener)
        model.start()
        model.pause()
        for _ in 0..<100 where listener.micOn { await Task.yield() }
        #expect(!listener.micOn, "off after a long pause (instant in tests)")
        #expect(model.status == .paused)
        model.resume()
        #expect(listener.micOn, "back on with play")
        #expect(listener.micStarts == 2)
        model.stop()
        #expect(!listener.micOn)
    }

    @Test func afterAPhoneCallTheMicIsTakenBack() async {
        let listener = FakeListener([])
        let model = makePausableVoiceModel(listener)
        model.start()
        audio.onEvent?(.interruptionBegan)
        #expect(model.status == .paused)
        audio.onEvent?(.interruptionEnded(shouldResume: true))
        #expect(model.status == .playing)
        #expect(listener.micOn)
        #expect(listener.micStarts == 2, "the mic is started again after the call")
        #expect(audio.voice && audio.active)
        model.stop()
        #expect(!listener.micOn)
    }

    @Test func inTheBackgroundTheMicIsOffAndAnswersAreReadOut() async {
        let listener = FakeListener([[FakeListener.rightLetter]])
        let model = makePausableVoiceModel(listener)
        listener.asking = { [weak model] in model?.turn?.presented }
        model.start()
        #expect(model.keepsScreenOn, "voice games keep the screen on")
        model.movedToBackground()
        #expect(!listener.micOn, "no orange dot while nothing can hear")
        await model.runner?.value
        #expect(model.status == .finished)
        #expect(listener.listens == 0, "speech recognition doesn't work in the background")
        #expect(speech.spoken.contains { $0.hasPrefix("The answer is") })
        #expect(model.isVoice, "voice comes back on screen")
        #expect(!model.keepsScreenOn)
    }

    @Test func backOnScreenTheMicComesBackOn() async {
        let listener = FakeListener([])
        let model = makePausableVoiceModel(listener)
        model.start()
        model.movedToBackground()
        model.movedToForeground()
        #expect(listener.micOn)
        #expect(listener.micStarts == 2)
        model.stop()
        #expect(!listener.micOn)
    }

    @Test func twoMissedAnswersStillAnnounceTheScores() async {
        let (model, _) = makeVoiceModel([[FakeListener.rightLetter]], questions: 3, length: 3)
        model.start()
        await model.runner?.value
        #expect(model.resultsAreReliable)
        #expect(model.showsFinalScores)
        #expect(speech.spoken.last?.contains("Mia got 10 points") == true)
    }

    @Test func moreThanTwoMissedAnswersMeansNoScoresOrWinner() async {
        let (model, _) = makeVoiceModel([[FakeListener.rightLetter]], questions: 4, length: 4)
        model.start()
        await model.runner?.value
        #expect(!model.resultsAreReliable, "3 answers weren't heard")
        #expect(!model.showsFinalScores)
        let ending = speech.spoken.last ?? ""
        #expect(ending.contains("Great job, Mia!"))
        #expect(!ending.contains("points") && !ending.contains("wins") && !ending.contains(Phrases.scoreFixNote))
        #expect(!ending.contains("heard"), "nothing is said about why")
        #expect(model.scoreboard.first?.points == 10, "the point still counts")
    }

    @Test func goingToTheBackgroundMeansNoScoresOrWinner() async {
        let (model, _) = makeVoiceModel([[FakeListener.rightLetter], [FakeListener.rightLetter]], questions: 2, length: 2)
        model.start()
        model.movedToBackground()
        model.movedToForeground()
        await model.runner?.value
        #expect(!model.resultsAreReliable)
        #expect(!model.showsFinalScores)
        let ending = speech.spoken.last ?? ""
        #expect(ending.contains("Great job, Mia!"))
        #expect(!ending.contains("points"))
        #expect((model.scoreboard.first?.points ?? 0) > 0, "points still count")
    }

    @Test func listenModeScoresAreAlwaysAnnounced() {
        let model = makeModel()
        model.start()
        model.movedToBackground()
        #expect(model.resultsAreReliable, "tapped scores don't depend on hearing")
        model.stop()
    }

    @Test func aBusyMicIsTriedAgainNextTurn() async {
        let listener = FakeListener([[FakeListener.rightLetter]],
                                    failure: SpeechListenerError.micBusy("call"), failsOnce: true)
        let config = SessionConfig(topics: ["animals"], players: [Player(id: "mia", name: "Mia", age: 7)],
                                   length: .questions(2))
        let model = ListenSessionModel(
            bank: makeBank(questions: 2), config: config, settings: ListenSettings(), duckOthers: true,
            dependencies: .init(speech: speech, cues: cues, sleeper: InstantSleeper(), audioSession: audio,
                                listener: listener),
            answerMode: .voice, rng: AnyRandomGenerator(seed: 1))
        listener.asking = { [weak model] in model?.turn?.presented }
        model.start()
        await model.runner?.value
        #expect(listener.listens == 2, "listened again after the mic was busy")
        #expect(model.isVoice)
        #expect(speech.spoken.contains { $0.hasPrefix("Correct") })
    }

    @Test func skippingMidQuestionKeepsItTheSamePlayersTurn() async {
        let mia = Player(id: "mia", name: "Mia", age: 7)
        let leo = Player(id: "leo", name: "Leo", age: 11)
        let listener = FakeListener([["skip"], [FakeListener.rightLetter], []])
        let model = ListenSessionModel(
            bank: makeBank(questions: 3, olderCount: 3), config: SessionConfig(topics: ["animals"], players: [mia, leo],
                                                                                length: .questions(1)),
            settings: ListenSettings(), duckOthers: true,
            dependencies: .init(speech: speech, cues: cues, sleeper: InstantSleeper(), audioSession: audio,
                                listener: listener),
            answerMode: .voice, rng: AnyRandomGenerator(seed: 2))
        listener.asking = { [weak model] in model?.turn?.presented }
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
        speech.holdWhen = { _ in model.canMark } // stop on Mia's answer reveal
        model.start()
        for _ in 0..<20000 where !speech.isHolding { await Task.yield() }
        #expect(model.turn?.player.id == "mia")
        model.mark(.correct)
        #expect(model.scoreboard.first { $0.player.id == "mia" }?.points == 10, "shows straight away")
        speech.release()
        await model.runner?.value
        #expect(model.scoreboard.first { $0.player.id == "mia" }?.points == 10)
        #expect(model.scoreboard.first { $0.player.id == "leo" }?.points == 0)
        #expect(model.showsFinalScores)
        #expect(speech.spoken.last?.contains("Mia got 10 points") == true || speech.spoken.last?.contains("Mia wins") == true)
        #expect(speech.spoken.last?.contains(Phrases.scoreFixNote) == true, "kids hear that scores can be fixed")

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
        let listener = FakeListener([[FakeListener.rightLetter]])
        let model = ListenSessionModel(
            bank: makeBank(questions: 1), config: SessionConfig(topics: ["animals"],
                                                                players: [Player(id: "mia", name: "Mia", age: 7)],
                                                                length: .questions(1)),
            settings: ListenSettings(), duckOthers: true,
            dependencies: .init(speech: speech, cues: cues, sleeper: InstantSleeper(), audioSession: audio,
                                listener: listener),
            answerMode: .voice, showScoreboard: false, rng: AnyRandomGenerator(seed: 1))
        listener.asking = { [weak model] in model?.turn?.presented }
        #expect(!model.showsScores)
        model.start()
        await model.runner?.value
        #expect(speech.spoken.contains { $0.hasPrefix("Correct!") }, "still cheered")
        #expect(!model.showsFinalScores)
        #expect(speech.spoken.last?.hasPrefix("That's the end of the game!") == true)
        #expect(speech.spoken.last?.contains("Great job, Mia!") == true)
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

    // MARK: Play again by voice

    /// Counts the next games started from the end of this one.
    @MainActor
    final class NextGames {
        var started = 0
        var available = true
        func hook() -> ListenSessionModel.PlayAgain {
            .init(isAvailable: { self.available }, start: { self.started += 1 })
        }
    }

    @Test func whenTheAppHearsThePlayersTheySayNewGame() async {
        let (model, listener) = makeVoiceModel([[FakeListener.rightLetter], ["New game!"]])
        let next = NextGames()
        model.playAgain = next.hook()
        model.start()
        await model.runner?.value

        #expect(speech.spoken.contains { $0.hasSuffix(Phrases.playAgainByVoice) })
        #expect(speech.spoken.last == Phrases.newGameStarting)
        #expect(listener.listens == 2, "one answer, then the reply")
        #expect(next.started == 1)
        #expect(!listener.micOn && !audio.active, "the next game takes the mic and audio over")
        #expect(!model.isListeningForNewGame)
    }

    @Test func silenceOrNoJustEndsTheGame() async {
        for reply in [[String](), ["No thanks"], ["Yes, I won!"]] {
            let (model, listener) = makeVoiceModel([[FakeListener.rightLetter], reply])
            let next = NextGames()
            model.playAgain = next.hook()
            model.start()
            await model.runner?.value
            #expect(speech.spoken.last?.hasSuffix(Phrases.playAgainByVoice) == true, "nothing more is said")
            #expect(next.started == 0)
            #expect(model.canPlayAgain, "the button is still there")
            #expect(!listener.micOn && !audio.active)
        }
    }

    @Test func playAgainByTapAfterTheGame() async {
        let (model, _) = makeVoiceModel([[FakeListener.rightLetter]])
        let next = NextGames()
        model.playAgain = next.hook()
        model.start()
        await model.runner?.value
        model.startNextGame()
        #expect(next.started == 1)
    }

    @Test func notOfferedByVoiceWhenHearingWasUnreliable() async {
        let (model, listener) = makeVoiceModel([[FakeListener.rightLetter]], questions: 4, length: 4)
        let next = NextGames()
        model.playAgain = next.hook()
        model.start()
        await model.runner?.value
        #expect(speech.spoken.last?.hasSuffix(Phrases.playAgain) == true, "start a new game by tap")
        #expect(listener.listens == 4, "no listening after the outro")
        #expect(model.canPlayAgain)
    }

    @Test func notOfferedWhenNothingWasHeardAllGame() async {
        let (model, listener) = makeVoiceModel([[]])
        model.playAgain = NextGames().hook()
        model.start()
        await model.runner?.value
        #expect(speech.spoken.last?.hasSuffix(Phrases.playAgain) == true)
        #expect(listener.listens == 1)
    }

    @Test func notOfferedWhenTodaysQuestionsHaveRunOut() async {
        let (model, listener) = makeVoiceModel([[FakeListener.rightLetter]])
        let next = NextGames()
        next.available = false
        model.playAgain = next.hook()
        model.start()
        await model.runner?.value
        #expect(speech.spoken.last?.hasSuffix(Phrases.playAgain) == true)
        #expect(listener.listens == 1)
        #expect(!model.canPlayAgain)
        model.startNextGame()
        #expect(next.started == 0)
    }

    @Test func sayingStopIsNotAskedToPlayMore() async {
        let (model, listener) = makeVoiceModel([["stop"]], questions: 2, length: 2)
        model.playAgain = NextGames().hook()
        model.start()
        await model.runner?.value
        #expect(model.status == .finished)
        #expect(speech.spoken.last?.hasSuffix(Phrases.playAgain) == true)
        #expect(listener.listens == 1)
    }

    @Test func doneDuringTheOutroTurnsTheMicOff() async {
        let (model, listener) = makeVoiceModel([[FakeListener.rightLetter], ["new game"]])
        let next = NextGames()
        model.playAgain = next.hook()
        speech.holdWhen = { $0.hasSuffix(Phrases.playAgainByVoice) }
        model.start()
        for _ in 0..<5000 where !speech.isHolding { await Task.yield() }
        #expect(model.status == .finished, "the finished screen shows during the outro")
        #expect(listener.micOn && audio.active, "still on, to hear \"new game\"")
        model.stop()
        #expect(!listener.micOn && !audio.active)
        speech.release()
        await model.runner?.value
        #expect(listener.listens == 1, "no listening after Done")
        #expect(next.started == 0)
    }

    @Test func listenModeKeepsTheTapLineButCanPlayAgain() async {
        let model = makeModel()
        let next = NextGames()
        model.playAgain = next.hook()
        model.start()
        await model.runner?.value
        #expect(speech.spoken.last?.hasSuffix(Phrases.playAgain) == true)
        #expect(model.canPlayAgain)
    }
}

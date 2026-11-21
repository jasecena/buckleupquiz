import Foundation
import Testing
@testable import QuizCore

@Suite("Quiz session")
struct SessionTests {
    @Test func neverRepeatsWithinSession() {
        let bank = sampleBank(perBand: 5)
        let config = SessionConfig(topics: ["geography"], players: [.listener(ageBand: .sixToEight)], length: .questions(50))
        var session = QuizSession(bank: bank, config: config, rng: AnyRandomGenerator(seed: 7))
        var ids: [String] = []
        while let turn = session.advance() { ids.append(turn.presented.question.id) }
        #expect(ids.count == 5)
        #expect(Set(ids).count == 5)
        #expect(session.isFinished)
    }

    @Test func stopsAtSessionLength() {
        let config = SessionConfig(topics: ["geography"], players: [.listener(ageBand: .nineToTen)], length: .questions(3))
        var session = QuizSession(bank: sampleBank(perBand: 10), config: config, rng: AnyRandomGenerator(seed: 1))
        var count = 0
        while session.advance() != nil { count += 1 }
        #expect(count == 3)
    }

    @Test func leavesQuestionsThatAreNotDueOrLearned() {
        let bank = sampleBank(perBand: 3)
        let player = Player.listener(ageBand: .sixToEight)
        var record = LearningRecord()
        record.record(.correct, for: "geography-6-8-0", on: 100) // box 2, due day 101
        for day in 100...131 { record.record(.correct, for: "geography-6-8-1", on: day) } // learned
        let config = SessionConfig(topics: ["geography"], players: [player], length: .questions(5))
        var session = QuizSession(bank: bank, config: config, learning: [player.id: record], day: 100,
                                  rng: AnyRandomGenerator(seed: 3))
        var ids: [String] = []
        while let turn = session.advance() { ids.append(turn.presented.question.id) }
        #expect(ids == ["geography-6-8-2"])
    }

    @Test func skippedBeforeTheAnswerLeavesTheBoxesAlone() {
        let player = Player.listener(ageBand: .sixToEight)
        let config = SessionConfig(topics: ["geography"], players: [player], length: .questions(2))
        var session = QuizSession(bank: sampleBank(), config: config, day: 10, rng: AnyRandomGenerator(seed: 5))
        session.advance()
        session.record(.skipped)
        session.advance()
        session.record(.notScored)
        session.mark(.heard)
        session.advance()
        #expect(session.isFinished)
        #expect(session.learning[player.id]?.cards.count == 1)
        #expect(session.learning[player.id]?.cards.values.first == ReviewCard(box: 2, due: 11, last: 10))
    }

    @Test func skippingKeepsTheTurnWithTheSamePlayer() {
        let mia = Player(id: "mia", name: "Mia", age: 7)
        let leo = Player(id: "leo", name: "Leo", age: 7)
        let config = SessionConfig(topics: ["geography"], players: [mia, leo], length: .questions(1))
        var session = QuizSession(bank: sampleBank(), config: config, day: 10, rng: AnyRandomGenerator(seed: 5))
        let first = session.advance()
        let replacement = session.advance(samePlayer: true)
        #expect(replacement?.player.id == "mia")
        #expect(replacement?.number == 1, "same question number")
        #expect(replacement?.presented.question.id != first?.presented.question.id)
        #expect(session.advance()?.player.id == "leo")
        #expect(session.advance() == nil, "the skipped question didn't use up the game's length")
        #expect(session.learning["mia"]?.card(first!.presented.question.id) == nil, "skipping leaves the boxes alone")
    }

    @Test func lengthIsQuestionsEachAndPlannedUpFront() {
        let players = ["a", "b", "c"].map { Player(id: $0, name: $0.uppercased(), age: 7) }
        let config = SessionConfig(topics: ["geography"], players: players, length: .questions(3))
        var session = QuizSession(bank: sampleBank(perBand: 10), config: config, day: 10, rng: AnyRandomGenerator(seed: 5))
        #expect(session.plannedEach == 3 && session.questionLimit == 9, "known before the game starts")
        #expect(session.plan.map(\.player.id) == ["a", "b", "c", "a", "b", "c", "a", "b", "c"])
        while session.advance() != nil {}
        #expect(players.map { session.turns(for: $0.id) } == [3, 3, 3])
    }

    @Test func aGameIsAtMost50Questions() {
        let six = (1...6).map { Player(id: "p\($0)", name: "P\($0)", age: 7) }
        #expect(SessionLength.questions(15).each(players: 6) == 8, "6 × 8 = 48")
        #expect(SessionLength.questions(5).each(players: 6) == 5)
        let session = QuizSession(bank: sampleBank(perBand: 60), config: SessionConfig(topics: ["geography"], players: six,
                                                                                       length: .questions(15)),
                                  day: 10)
        #expect(session.plan.count <= SessionLength.maxQuestions)
    }

    @Test func aShortRoundIsDroppedSoEveryoneStaysEqual() {
        let mia = Player(id: "mia", name: "Mia", age: 7)
        let leo = Player(id: "leo", name: "Leo", age: 7)
        // 5 questions for their age and nothing twice a day: 2 full rounds, the 3rd can't finish.
        let config = SessionConfig(topics: ["geography"], players: [mia, leo], length: .questions(5))
        let session = QuizSession(bank: sampleBank(perBand: 5), config: config, day: 10, rng: AnyRandomGenerator(seed: 5))
        #expect(session.requestedEach == 5)
        #expect(session.plannedEach == 2)
        #expect(session.plan.count == 4)
    }

    @Test func theFreshBudgetLimitsNewQuestionsButNotReviews() {
        let mia = Player(id: "mia", name: "Mia", age: 7)
        var record = LearningRecord()
        record.record(.incorrect, for: "geography-6-8-0", on: 9) // due again: a free review
        let config = SessionConfig(topics: ["geography"], players: [mia], length: .questions(10))
        var session = QuizSession(bank: sampleBank(perBand: 10), config: config, learning: ["mia": record], day: 10,
                                  budget: FreshBudget(perTopic: ["geography": 2], shared: 1),
                                  rng: AnyRandomGenerator(seed: 5))
        #expect(session.plannedEach == 4, "1 review + 2 from the topic + 1 shared")
        while session.advance() != nil { session.record(.correct) }
        #expect(session.charges[.topic] == 2 && session.charges[.shared] == 1 && session.charges[.free] == 1)
    }

    @Test func aTopicWithNothingForThisAgeUsesTheNearestAge() {
        let mia = Player(id: "mia", name: "Mia", age: 7)
        let leo = Player(id: "leo", name: "Leo", age: 11)
        let questions = (0..<5).map { makeQuestion("g-\($0)", topic: "geography", band: .sixToEight) }
        let bank = QuestionBank(topics: sampleBank().topics, questions: questions)
        var session = QuizSession(bank: bank, config: SessionConfig(topics: ["geography"], players: [mia, leo],
                                                                    length: .questions(4)),
                                  day: 10, rng: AnyRandomGenerator(seed: 5))
        while session.advance() != nil { session.record(.unheard) }
        #expect(session.turns(for: "mia") == 2 && session.turns(for: "leo") == 2)
    }

    @Test func aGrownUpCanFixAScoreWithinRange() {
        let mia = Player(id: "mia", name: "Mia", age: 7)
        let config = SessionConfig(topics: ["geography"], players: [mia], length: .questions(3))
        var session = QuizSession(bank: sampleBank(), config: config, day: 10, rng: AnyRandomGenerator(seed: 5))
        while session.advance() != nil { session.record(.unheard) }
        #expect(session.maxPoints(for: "mia") == 35, "10 + 10 + 15")
        session.setPoints(20, for: "mia")
        #expect(session.scoreboard.first?.points == 20)
        session.setPoints(500, for: "mia")
        #expect(session.scoreboard.first?.points == 35)
        session.setPoints(-10, for: "mia")
        #expect(session.scoreboard.first?.points == 0)
    }

    @Test func unheardAnswerChangesNothing() {
        let player = Player(id: "mia", name: "Mia", age: 7)
        let config = SessionConfig(topics: ["geography"], players: [player], length: .questions(3))
        var session = QuizSession(bank: sampleBank(), config: config, day: 10, rng: AnyRandomGenerator(seed: 5))
        session.advance()
        session.record(.correct)
        session.advance()
        session.record(.correct)
        session.advance()
        session.record(.unheard)
        session.advance()
        let stats = session.scores.stats(for: "mia")
        #expect(stats.points == 20)
        #expect(stats.currentStreak == 2, "not being heard doesn't break a streak")
        #expect(stats.attempted == 2)
        #expect(session.learning["mia"]?.cards.count == 2, "the unheard question's boxes are untouched")
    }

    @Test func rotatesPlayersWithTheirOwnAgeBand() {
        let mia = Player(id: "mia", name: "Mia", ageBand: .sixToEight)
        let leo = Player(id: "leo", name: "Leo", ageBand: .elevenToTwelve)
        let config = SessionConfig(topics: ["geography"], players: [mia, leo], length: .questions(3))
        var session = QuizSession(bank: sampleBank(perBand: 5), config: config, rng: AnyRandomGenerator(seed: 9))
        var turns: [Turn] = []
        while let t = session.advance() { turns.append(t) }
        #expect(turns.map(\.player.name) == ["Mia", "Leo", "Mia", "Leo", "Mia", "Leo"])
        for turn in turns {
            #expect(turn.presented.question.ageBand == turn.player.ageBand)
        }
    }

    @Test func respectsMinAgeAndTalkAboutToggle() {
        let topic = Topic(id: "manners", name: "Manners", symbol: "s", color: "#000000", category: .values, isFree: true)
        let bank = QuestionBank(topics: [topic], questions: [
            makeQuestion("old", topic: "manners", band: .elevenToTwelve, minAge: 12),
            makeQuestion("chat", topic: "manners", band: .elevenToTwelve, type: .talkAbout, answer: nil),
            makeQuestion("ok", topic: "manners", band: .elevenToTwelve),
        ])
        let eleven = Player(id: "p", name: "Pip", ageBand: .elevenToTwelve, age: 11)
        let selector = QuestionSelector(bank: bank, topics: ["manners"], includeTalkAbout: false)
        #expect(selector.pool(for: eleven).map(\.id) == ["ok"])
    }

    @Test func recordsScoresAndTreatsTalkAboutAsUnscored() {
        let topic = Topic(id: "manners", name: "Manners", symbol: "s", color: "#000000", category: .values, isFree: true)
        let bank = QuestionBank(topics: [topic], questions: [
            makeQuestion("chat", topic: "manners", type: .talkAbout, answer: nil),
        ])
        let mia = Player(id: "mia", name: "Mia", ageBand: .sixToEight)
        var session = QuizSession(bank: bank, config: SessionConfig(topics: ["manners"], players: [mia]),
                                  rng: AnyRandomGenerator(seed: 1))
        session.advance()
        let event = session.record(.correct)
        #expect(event?.outcome == .notScored)
        #expect(event?.pointsAwarded == 0)
        #expect(session.record(.correct) == nil, "a turn can only be recorded once")
    }

    @Test func unrecordedTurnCountsAsSkipped() {
        let config = SessionConfig(topics: ["geography"], players: [Player(id: "a", name: "A", ageBand: .sixToEight)])
        var session = QuizSession(bank: sampleBank(), config: config, rng: AnyRandomGenerator(seed: 1))
        session.advance()
        session.record(.correct)
        session.advance()
        session.advance()
        #expect(session.scores.stats(for: "a").currentStreak == 0)
        #expect(session.scores.stats(for: "a").attempted == 1)
    }

    @Test func talkAboutIsNotBoxedButRemembered() {
        let topic = Topic(id: "manners", name: "Manners", symbol: "s", color: "#000000", category: .values, isFree: true)
        let bank = QuestionBank(topics: [topic], questions: [
            makeQuestion("chat", topic: "manners", type: .talkAbout, answer: nil),
        ])
        let mia = Player(id: "mia", name: "Mia", ageBand: .sixToEight)
        var session = QuizSession(bank: bank, config: SessionConfig(topics: ["manners"], players: [mia], includeTalkAbout: true),
                                  rng: AnyRandomGenerator(seed: 1))
        session.advance()
        session.record(.correct)
        session.stop()
        #expect(session.learning["mia"]?.cards.isEmpty == true)
        #expect(session.learning["mia"]?.talkedAbout == ["chat"])
    }
}

@Suite("Content loading")
struct ContentLoadingTests {
    @Test func loadsFixtureContent() throws {
        let bank = try DirectoryQuestionSource(root: fixtureContentURL()).loadBankSync()
        #expect(bank.topics.map(\.id) == ["geography", "manners"])
        #expect(bank.questions.count == 4)
        #expect(bank.questionCount(topic: "geography") == 2)
        let tasmania = try #require(bank.questions.first { $0.id == "geo-0001" })
        #expect(tasmania.acceptedAnswers == ["hobart", "hobart city"])
        let chat = try #require(bank.questions.first { $0.id == "man-0002" })
        #expect(chat.answer == nil)
        #expect(chat.acceptedAnswers.isEmpty)
    }

    @Test func missingCatalogueThrows() {
        let source = DirectoryQuestionSource(root: URL(fileURLWithPath: "/nonexistent"))
        #expect(throws: QuestionSourceError.self) { try source.loadBankSync() }
    }
}

@Suite("Listen script")
struct ListenScriptTests {
    @Test func multipleChoiceSteps() {
        var q = makeQuestion(text: "What is the capital city of Tasmania?", answer: "Hobart")
        q.funFact = "Hobart is Australia's second-oldest capital city."
        let turn = Turn(number: 1, player: .listener(ageBand: .sixToEight), presented: present(q))
        let steps = ListenScript.steps(for: turn, category: .knowledge, settings: ListenSettings(), addressPlayer: false)
        #expect(steps == [
            .say("Buckle up, kids… question one!", .number),
            .say("What is the capital city of Tasmania?", .question),
            .say("A: Hobart. B: Launceston. C: Darwin.", .options),
            .cue(.think),
            .think(seconds: 6),
            .say("The answer is… A: Hobart!", .answer),
            .say("Hobart is Australia's second-oldest capital city.", .followUp),
            .wait(seconds: 2),
        ])
    }

    @Test func valuesQuestionReadsOptionsAndExplanation() {
        var q = makeQuestion(topic: "manners", type: .multipleChoice, text: "Your friend falls over.",
                             options: ["Laugh", "Help them up", "Keep playing"], answer: "Help them up")
        q.explanation = "Helping shows you care."
        let mia = Player(id: "mia", name: "Mia", ageBand: .sixToEight)
        var settings = ListenSettings()
        settings.funFacts = false
        let steps = ListenScript.steps(for: Turn(number: 2, player: mia, presented: present(q)),
                                       category: .values, settings: settings, addressPlayer: true)
        #expect(steps == [
            .say("Question two.", .number),
            .say("Mia, this one's for you!", .number),
            .say("Your friend falls over.", .question),
            .say("A: Laugh. B: Help them up. C: Keep playing.", .options),
            .cue(.think),
            .think(seconds: 6),
            .say("The best choice is… B: Help them up!", .answer),
            .say("Helping shows you care.", .followUp),
            .wait(seconds: 2),
        ])
    }

    @Test func laterTurnsJustSayTheNameAndPause() {
        let mia = Player(id: "mia", name: "Mia", ageBand: .sixToEight)
        let steps = ListenScript.steps(for: Turn(number: 3, player: mia, presented: present(makeQuestion(text: "Capital?"))),
                                       category: .knowledge, settings: ListenSettings(), addressPlayer: true,
                                       firstTurnForPlayer: false)
        #expect(Array(steps.prefix(4)) == [
            .say("Question three.", .number),
            .say("Mia.", .number),
            .wait(seconds: 0.6),
            .say("Capital?", .question),
        ])
        #expect(!steps.contains { if case .say(let text, _) = $0 { text.contains("for you") } else { false } })
    }

    @Test func talkAboutDefaultsTo30SecondsAndOffersNoLimit() throws {
        #expect(ListenSettings().talkTime == 30, "nobody waits forever by default")
        var noLimit = ListenSettings()
        noLimit.talkTime = nil
        let saved = try JSONDecoder().decode(ListenSettings.self, from: JSONEncoder().encode(noLimit))
        #expect(saved.talkTime == nil, "a chosen No limit is remembered")
        let older = try JSONDecoder().decode(ListenSettings.self, from: Data(#"{"thinkTime": 6}"#.utf8))
        #expect(older.talkTime == 30)
    }

    @Test func talkAboutCanHaveNoTimeLimit() {
        let q = makeQuestion(type: .talkAbout, text: "What made you smile today?", answer: nil)
        var settings = ListenSettings()
        settings.talkTime = nil
        let steps = ListenScript.steps(for: Turn(number: 3, player: .listener(ageBand: .sixToEight), presented: present(q)),
                                       category: .values, settings: settings, addressPlayer: false)
        #expect(!steps.contains { if case .think = $0 { true } else { false } })
        #expect(!steps.contains(.cue(.think)))
        let discuss = steps.firstIndex(of: .discuss(seconds: nil))
        let chat = steps.firstIndex(of: .say("Great chat!", .answer))
        #expect(discuss != nil && chat != nil && discuss! < chat!)
        #expect(steps.contains(.say(Phrases.talkItOver, .options)))
    }

    @Test func parentModeHasItsOwnTalkTimer() {
        let q = makeQuestion(type: .talkAbout, text: "What made you smile today?", answer: nil)
        var settings = ListenSettings()
        settings.thinkTime = 5
        settings.talkTime = 120
        let steps = ListenScript.steps(for: Turn(number: 1, player: .listener(ageBand: .sixToEight), presented: present(q)),
                                       category: .values, settings: settings, addressPlayer: false)
        #expect(steps.contains(.discuss(seconds: 120)), "separate from think time, not a multiple of it")
    }

    @Test func thinkTimeIsClamped() {
        var settings = ListenSettings()
        settings.thinkTime = 99
        let turn = Turn(number: 1, player: .listener(ageBand: .sixToEight), presented: present(makeQuestion()))
        let steps = ListenScript.steps(for: turn, category: nil, settings: settings, addressPlayer: false)
        #expect(steps.contains(.think(seconds: 20)))
    }

    @Test func feedbackNeverSoundsLikeFailure() {
        var rng = SeededGenerator(seed: 1)
        let values = present(makeQuestion(options: ["Laugh", "Help", "Run off"], answer: "Help"))
        let hobart = present(makeQuestion(answer: "Hobart"))
        for outcome in [AnswerOutcome.incorrect, .timedOut, .unheard] {
            #expect(Phrases.feedback(outcome, presented: values, category: .values, using: &rng)
                == "The best choice is… B: Help!")
            #expect(Phrases.feedback(outcome, presented: hobart, category: .knowledge, using: &rng)
                == "The answer is… A: Hobart!")
        }
    }

    @Test func listenOutroNamesThePlayers() {
        let mia = Player(id: "m", name: "Mia", age: 7)
        let leo = Player(id: "l", name: "Leo", age: 11)
        #expect(Phrases.listenOutro(players: [mia, leo]) == "That's the end of the ride! Great job, Mia and Leo!")
        #expect(Phrases.listenOutro(players: [.listener(ageBand: .sixToEight)])
            == "That's the end of the ride! Great listening, everyone!")
    }

    @Test func settingsFromOlderBuildsStillDecode() throws {
        let old = #"{"thinkTime": 12, "readOptions": false}"#
        let settings = try JSONDecoder().decode(ListenSettings.self, from: Data(old.utf8))
        #expect(settings.thinkTime == 12)
        #expect(settings.funFacts == true)
    }
}

@Suite("Players and ages")
struct PlayerAgeTests {
    @Test(arguments: [(4, AgeBand.sixToEight), (6, .sixToEight), (8, .sixToEight), (9, .nineToTen),
                      (10, .nineToTen), (11, .elevenToTwelve), (12, .elevenToTwelve), (14, .elevenToTwelve)])
    func ageMapsToBand(age: Int, band: AgeBand) {
        #expect(AgeBand(age: age) == band)
        #expect(Player(id: "p", name: "P", age: age).ageBand == band)
    }
}

@Suite("Repository content")
struct RepositoryContentTests {
    /// The real bundled content must decode with the same models the app uses.
    @Test func bundledContentDecodes() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // QuizCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // QuizCore
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent()
        let bank = try DirectoryQuestionSource(root: repoRoot.appendingPathComponent("Content")).loadBankSync()
        #expect(bank.topics.filter(\.isFree).count == 3)
        #expect(!bank.questions.isEmpty)
        let matcher = AnswerMatcher()
        var rng = SeededGenerator(seed: 1)
        for q in bank.questions where q.type.isScored {
            let presented = PresentedQuestion(question: q, shuffleOptions: true, using: &rng)
            if q.type.hasOptions {
                #expect(presented.correctOptionIndex != nil, "\(q.id): answer must be an option")
            }
            // The canonical answer must always be accepted when said back.
            let answer = try #require(q.answer)
            #expect(matcher.match(transcriptions: [answer], to: presented) == .correct(heard: answer), "\(q.id)")
        }
    }
}

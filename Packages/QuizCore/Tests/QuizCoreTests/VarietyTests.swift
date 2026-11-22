import Testing
@testable import QuizCore

/// Breathers between questions and long or hard questions read twice (`TurnVariety`).
@Suite("Turn variety")
struct VarietyTests {
    let short = makeQuestion(text: "Capital of Tasmania?")
    var hard: Question {
        var q = makeQuestion(text: "Capital of Tasmania?")
        q.difficulty = 3
        return q
    }
    let long = makeQuestion(text: "Which city is the capital of the island state that sits south of Victoria?")

    func turn(_ q: Question, number: Int = 2) -> Turn {
        Turn(number: number, player: .listener(ageBand: .sixToEight), presented: present(q))
    }

    func varieties(_ q: Question, number: Int = 2, firstQuestion: Bool = false, count: Int = 400) -> [TurnVariety] {
        var rng = SeededGenerator(seed: 7)
        return (0..<count).map { _ in
            TurnVariety.random(for: turn(q, number: number), firstQuestion: firstQuestion, using: &rng)
        }
    }

    @Test func noBreatherBeforeTheFirstQuestion() {
        #expect(varieties(short, number: 1, firstQuestion: true).allSatisfy { $0.breather == nil })
    }

    @Test func breathersAreMixedAndShort() {
        let breathers = varieties(short).compactMap(\.breather)
        #expect(breathers.count == 400, "something between every pair of questions")
        var silences = 0, phrases = 0, jingles = 0
        for breather in breathers {
            switch breather {
            case .silence(let seconds):
                silences += 1
                #expect((1...2).contains(seconds))
            case .phrase(let text):
                phrases += 1
                #expect(Phrases.betweenQuestions.contains(text))
            case .jingle:
                jingles += 1
            }
        }
        #expect(silences > 100 && phrases > 100 && jingles > 50)
    }

    @Test func onlyLongOrHardQuestionsAreReadTwice() {
        #expect(!TurnVariety.isLongOrHard(short))
        #expect(TurnVariety.isLongOrHard(hard))
        #expect(TurnVariety.isLongOrHard(long))
        #expect(varieties(short).allSatisfy { !$0.repeatsQuestion })
        let repeats = varieties(long).filter(\.repeatsQuestion).count
        #expect(repeats > 100 && repeats < 220, "about 40% of the time, not always")
        #expect(!TurnVariety.isLongOrHard(makeQuestion(type: .talkAbout, text: long.question, answer: nil)))
    }

    @Test func theScriptPutsTheBreatherFirstAndTheRepeatBeforeTheOptions() {
        let variety = TurnVariety(breather: .phrase("Thinking caps on!"), repeatsQuestion: true)
        let steps = ListenScript.steps(for: turn(long), category: .knowledge, settings: ListenSettings(),
                                       addressPlayer: false, variety: variety)
        #expect(steps[0] == .say("Thinking caps on!", .filler))
        #expect(steps[1] == .say("Question two.", .number))
        let question = steps.firstIndex(of: .say(long.question, .question))!
        #expect(steps[question + 1] == .say(Phrases.onceMore, .filler))
        #expect(steps[question + 2] == .say(long.question, .filler))
        #expect(steps[question + 3] == .say(Phrases.options(present(long))!, .options))
    }

    @Test func aJingleHasTimeToPlay() {
        let steps = ListenScript.steps(for: turn(short), category: .knowledge, settings: ListenSettings(),
                                       addressPlayer: false, variety: TurnVariety(breather: .jingle))
        #expect(Array(steps.prefix(2)) == [.cue(.jingle), .wait(seconds: ListenScript.jingleLength)])
        let quiet = ListenScript.steps(for: turn(short), category: .knowledge, settings: ListenSettings(),
                                       addressPlayer: false, variety: TurnVariety(breather: .silence(seconds: 1.5)))
        #expect(quiet.first == .wait(seconds: 1.5))
    }

    @Test func plainScriptHasNoVariety() {
        let steps = ListenScript.steps(for: turn(long), category: .knowledge, settings: ListenSettings(),
                                       addressPlayer: false)
        #expect(steps.first == .say("Question two.", .number))
        #expect(!steps.contains(.say(Phrases.onceMore, .filler)))
    }
}

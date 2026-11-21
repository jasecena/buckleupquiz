import Foundation
import Testing
@testable import QuizCore

@Suite("Leitner boxes")
struct LeitnerTests {
    @Test func rightAnswersSpaceOutTodayTomorrowThen2_4_8_16Days() {
        var record = LearningRecord()
        var day = 0
        var waits: [Int] = []
        for _ in 0..<5 {
            record.record(.correct, for: "q", on: day)
            let card = record.card("q")!
            waits.append(card.due - day)
            day = card.due
        }
        #expect(waits == [1, 2, 4, 8, 16])
        #expect(record.card("q")?.box == 6)
        record.record(.correct, for: "q", on: day)
        #expect(record.card("q")?.isLearned == true)
        #expect(!record.isDue("q", on: day + 1000), "learned questions aren't asked again")
    }

    @Test func wrongAnswerStartsOverToday() {
        var record = LearningRecord()
        for day in 0..<3 { record.record(.correct, for: "q", on: day) }
        #expect(record.card("q")?.box == 4)
        record.record(.incorrect, for: "q", on: 20)
        #expect(record.card("q") == ReviewCard(box: 1, due: 20))
        #expect(record.isDue("q", on: 20))
    }

    @Test func heardCountsAsRight() {
        var record = LearningRecord()
        record.record(.heard, for: "q", on: 5)
        #expect(record.card("q") == ReviewCard(box: 2, due: 6, last: 5))
    }

    @Test func calendarDaysNotHours() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Australia/Sydney"))
        let lateNight = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 23, minute: 50)))
        let nextMorning = lateNight.addingTimeInterval(20 * 60)
        #expect(LearningDay.number(for: nextMorning, calendar: calendar)
            == LearningDay.number(for: lateNight, calendar: calendar) + 1)
    }

    @Test func recordsSurviveMissingKeys() throws {
        let record = try JSONDecoder().decode(LearningRecord.self, from: Data("{}".utf8))
        #expect(record.cards.isEmpty)
        let roundTrip = try JSONDecoder().decode(
            LearningRecord.self, from: JSONEncoder().encode(LearningRecord(cards: ["q": ReviewCard(box: 3, due: 9)])))
        #expect(roundTrip.card("q") == ReviewCard(box: 3, due: 9))
    }
}

@Suite("Review mix")
struct ReviewMixTests {
    let mia = Player(id: "mia", name: "Mia", ageBand: .sixToEight)
    let leo = Player(id: "leo", name: "Leo", ageBand: .sixToEight)

    func ids(_ n: Int) -> [String] { (0..<n).map { "geography-6-8-\($0)" } }

    @Test func eightyPercentNewTenOwnTenShared() {
        var rng = SeededGenerator(seed: 4)
        for (turns, reviews) in [(20, 2), (10, 1), (30, 3)] {
            let plan = ReviewMix.plan(turns: turns, using: &rng)
            #expect(plan.count == turns)
            #expect(plan.first == .new, "start with something fresh")
            #expect(plan.filter { $0 == .ownReview }.count == reviews)
            #expect(plan.filter { $0 == .sharedReview }.count == reviews)
        }
    }

    @Test func reviewsAreAShareNotTheWholeSession() {
        var record = LearningRecord()
        for id in ids(30) { record.record(.incorrect, for: id, on: 99) } // 30 due
        let config = SessionConfig(topics: ["geography"], players: [mia], length: .questions(20))
        var session = QuizSession(bank: sampleBank(perBand: 60), config: config, learning: ["mia": record], day: 100,
                                  rng: AnyRandomGenerator(seed: 2))
        var kinds: [TurnKind] = []
        while let turn = session.advance() { kinds.append(turn.kind) }
        #expect(kinds.count == 20)
        #expect(kinds.first == .new)
        // On her own, Mia's shared slots fall back to her own reviews: 4 of 20.
        #expect(kinds.filter { $0 == .ownReview }.count == 4)
        #expect(kinds.filter { $0 == .new }.count == 16)
    }

    @Test func sharedReviewsComeFromWhatTheOthersHadYesterday() {
        var leoRecord = LearningRecord()
        for id in ids(5) { leoRecord.record(.incorrect, for: id, on: 99) }
        let config = SessionConfig(topics: ["geography"], players: [mia, leo], length: .questions(20))
        var session = QuizSession(bank: sampleBank(perBand: 40), config: config, learning: ["leo": leoRecord],
                                  day: 100, rng: AnyRandomGenerator(seed: 6))
        var turns: [Turn] = []
        while let turn = session.advance() { turns.append(turn) }
        let miaShared = turns.filter { $0.player.id == "mia" && $0.kind == .sharedReview }
        #expect(!miaShared.isEmpty)
        #expect(miaShared.allSatisfy { ids(5).contains($0.presented.question.id) })
        #expect(turns.filter { $0.kind != .new }.count <= 4, "about 20% reviews")
        #expect(Set(turns.map(\.presented.question.id)).count == turns.count, "nothing twice in a day")
    }

    @Test func nobodyGetsAQuestionTwiceInOneDay() {
        var leoRecord = LearningRecord()
        leoRecord.record(.correct, for: "geography-6-8-0", on: 100) // Leo had it this morning
        let config = SessionConfig(topics: ["geography"], players: [mia], length: .endless)
        var session = QuizSession(bank: sampleBank(perBand: 3), config: config, learning: ["leo": leoRecord],
                                  day: 100, rng: AnyRandomGenerator(seed: 1))
        var asked: [String] = []
        while let turn = session.advance() { asked.append(turn.presented.question.id) }
        #expect(asked.sorted() == ["geography-6-8-1", "geography-6-8-2"])
    }

    @Test func bystandersMoveUpWhenRightAndStayPutWhenWrong() {
        let config = SessionConfig(topics: ["geography"], players: [mia, leo], length: .questions(2))
        var session = QuizSession(bank: sampleBank(perBand: 2), config: config, day: 50, rng: AnyRandomGenerator(seed: 1))
        let first = session.advance()!   // Mia's turn
        session.record(.correct)
        let second = session.advance()!  // Leo's turn
        session.record(.incorrect)
        session.advance()
        let q1 = first.presented.question.id, q2 = second.presented.question.id
        #expect(session.learning["mia"]?.card(q1)?.box == 2)
        #expect(session.learning["leo"]?.card(q1)?.box == 2, "Leo heard Mia get it right")
        #expect(session.learning["leo"]?.card(q2)?.box == 1, "Leo starts over")
        #expect(session.learning["mia"]?.card(q2) == nil, "Mia isn't sent back for Leo's miss")
    }

    @Test func bystandersInAnotherBandAreLeftAlone() {
        let older = Player(id: "ava", name: "Ava", ageBand: .elevenToTwelve)
        let config = SessionConfig(topics: ["geography"], players: [mia, older], length: .questions(1))
        var session = QuizSession(bank: sampleBank(perBand: 2), config: config, day: 50, rng: AnyRandomGenerator(seed: 1))
        session.advance()
        session.record(.correct)
        session.advance()
        #expect(session.learning["ava"] == nil)
    }
}

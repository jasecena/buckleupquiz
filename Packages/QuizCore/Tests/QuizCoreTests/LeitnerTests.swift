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
        #expect(record.card("q") == ReviewCard(box: 2, due: 6))
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

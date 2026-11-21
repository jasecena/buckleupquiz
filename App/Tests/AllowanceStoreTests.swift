import Foundation
import QuizCore
import Testing
@testable import BuckleUpQuiz

@MainActor
@Suite("Allowance")
struct AllowanceStoreTests {
    func makeStore() -> AllowanceStore {
        AllowanceStore(defaults: UserDefaults(suiteName: "allowance-\(UUID())")!)
    }

    let animals = Topic(id: "animals", name: "Animals", symbol: "pawprint", color: "#F39C12", category: .knowledge, isFree: true)
    let manners = Topic(id: "manners", name: "Manners", symbol: "heart", color: "#F39C12", category: .values, isFree: true)

    @Test func freeTopicsStartWith30AndMannersWith10() {
        let store = makeStore()
        let bank = makeBank(questions: 40)
        let budget = store.budget(for: [animals, manners], bank: bank, hasBasic: false, day: 1)
        #expect(budget.perTopic["animals"] == 30)
        #expect(budget.perTopic["manners"] == 10)
        #expect(budget.shared == 0)
    }

    @Test func twoMorePerDayOpenedButNotForManners() {
        let store = makeStore()
        store.appOpened(day: 1, freeTopics: [animals, manners])
        store.appOpened(day: 1, freeTopics: [animals, manners])
        store.appOpened(day: 4, freeTopics: [animals, manners])
        store.appOpened(day: 5, freeTopics: [animals, manners])
        #expect(store.freeLimit(for: animals) == 34, "two days opened after the first, not three")
        #expect(store.freeLimit(for: manners) == 10)
    }

    @Test func playedQuestionsAreChargedOnceAndPacksPayTheRest() {
        let store = makeStore()
        #expect(store.creditPack(transactionID: 7))
        #expect(!store.creditPack(transactionID: 7), "a transaction is credited once")
        #expect(store.state.packCredits == 50)
        store.charge(["a": .topic, "b": .shared, "c": .shared, "d": .free], hasBasic: false, day: 1)
        #expect(store.state.packCredits == 48)
        #expect(store.state.unlocked == ["a", "b", "c", "d"])
    }

    @Test func basicHas40ADayThenUsesPacks() {
        let store = makeStore()
        store.creditPack(transactionID: 1)
        var asked: [String: FreshBudget.Source] = [:]
        for i in 0..<45 { asked["q\(i)"] = .shared }
        store.charge(asked, hasBasic: true, day: 3)
        #expect(store.basicLeft(on: 3) == 0)
        #expect(store.state.packCredits == 45)
        #expect(store.basicLeft(on: 4) == 40, "a new day, a new 40")
        let budget = store.budget(for: [animals], bank: makeBank(questions: 5), hasBasic: true, day: 4)
        #expect(budget.shared == 85)
    }
}

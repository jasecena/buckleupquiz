import Foundation
import Observation
import QuizCore

/// How many new questions the family can have (ADR-0022). A question costs one, once: the first
/// time anyone in the family hears it. Reviews and repeats are always free.
///
/// - **Free:** the free topics (Animals, Geography) start with 30 questions each and get 2 more
///   each day the app is opened; Manners & Friendship has 10 and no top-up.
/// - **Question packs:** 50 new questions each, for any topic you can open. They never expire.
/// - **BuckleUp Basic:** every topic, and 40 new questions a day (packs add on top).
@MainActor
@Observable
final class AllowanceStore {
    static let starterPerTopic = 30
    static let starterValues = 10
    static let dailyTopUp = 2
    static let basicDaily = 40
    static let packSize = 50

    struct State: Codable, Equatable {
        /// Question ids the family has heard: never charged again.
        var unlocked: Set<String> = []
        /// Extra free questions per topic from daily top-ups.
        var topUps: [String: Int] = [:]
        var lastOpenDay: Int?
        /// New questions bought in packs and not used yet.
        var packCredits = 0
        /// BuckleUp Basic's daily allowance used, and the day it was used.
        var basicDay: Int?
        var basicUsed = 0
        /// Pack purchases already credited (so a replayed transaction never counts twice).
        var creditedTransactions: Set<UInt64> = []
        /// Packs bought ever, for the record.
        var packsBought = 0
    }

    private(set) var state: State {
        didSet { if state != oldValue { save() } }
    }
    private let defaults: UserDefaults
    private let key = "allowance.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode(State.self, from: data) {
            state = saved
        } else {
            state = State()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: key) }
    }

    /// Anything the family already played before metering started counts as theirs.
    func seed(with ids: some Sequence<String>) {
        state.unlocked.formUnion(ids)
    }

    /// The daily top-up: 2 more free questions in each free knowledge topic, once per day the
    /// app is opened (days it isn't opened don't add up).
    func appOpened(day: Int, freeTopics: [Topic]) {
        guard state.lastOpenDay != day else { return }
        if state.lastOpenDay != nil {
            for topic in freeTopics where topic.category == .knowledge {
                state.topUps[topic.id, default: 0] += Self.dailyTopUp
            }
        }
        state.lastOpenDay = day
    }

    /// Free questions a topic allows in total (starter + top-ups).
    func freeLimit(for topic: Topic) -> Int {
        topic.category == .knowledge ? Self.starterPerTopic + state.topUps[topic.id, default: 0] : Self.starterValues
    }

    func basicLeft(on day: Int) -> Int {
        state.basicDay == day ? max(0, Self.basicDaily - state.basicUsed) : Self.basicDaily
    }

    /// What a game may spend on new questions.
    func budget(for topics: [Topic], bank: QuestionBank, hasBasic: Bool, day: Int) -> FreshBudget {
        if hasBasic {
            return FreshBudget(shared: saturatingAdd(basicLeft(on: day), state.packCredits), unlocked: state.unlocked)
        }
        var perTopic: [String: Int] = [:]
        for topic in topics where topic.isFree {
            let heard = bank.questions(topic: topic.id).filter { state.unlocked.contains($0.id) }.count
            perTopic[topic.id] = max(0, freeLimit(for: topic) - heard)
        }
        return FreshBudget(perTopic: perTopic, shared: state.packCredits, unlocked: state.unlocked)
    }

    /// New questions left today in one topic (for Home and Settings).
    func newQuestionsLeft(in topic: Topic, bank: QuestionBank, hasBasic: Bool, day: Int) -> Int {
        let budget = budget(for: [topic], bank: bank, hasBasic: hasBasic, day: day)
        let unheard = bank.questions(topic: topic.id).filter { !state.unlocked.contains($0.id) && $0.type != .talkAbout }.count
        return min(unheard, saturatingAdd(budget.perTopic[topic.id] ?? 0, budget.shared))
    }

    /// After a game: what was asked is now the family's, and shared costs are paid from the
    /// subscription's daily allowance first, then packs.
    func charge(_ asked: [String: FreshBudget.Source], hasBasic: Bool, day: Int) {
        var next = state
        next.unlocked.formUnion(asked.keys)
        var shared = asked.values.filter { $0 == .shared }.count
        if hasBasic {
            if next.basicDay != day {
                next.basicDay = day
                next.basicUsed = 0
            }
            let fromDaily = min(shared, max(0, Self.basicDaily - next.basicUsed))
            next.basicUsed += fromDaily
            shared -= fromDaily
        }
        next.packCredits = max(0, next.packCredits - shared)
        state = next
    }

    /// A question pack was bought. Returns false if this transaction was already credited.
    @discardableResult
    func creditPack(transactionID: UInt64) -> Bool {
        guard !state.creditedTransactions.contains(transactionID) else { return false }
        state.creditedTransactions.insert(transactionID)
        state.packCredits += Self.packSize
        state.packsBought += 1
        return true
    }

    private func saturatingAdd(_ a: Int, _ b: Int) -> Int {
        let (sum, overflow) = a.addingReportingOverflow(b)
        return overflow ? .max : sum
    }
}

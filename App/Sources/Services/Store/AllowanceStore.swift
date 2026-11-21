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

    /// Everything here only grows (or is a max), so copies from two devices, iCloud and the
    /// Keychain merge without losing anything or handing out free questions twice (ADR-0023).
    struct State: Codable, Equatable {
        /// Question ids the family has heard: never charged again.
        var unlocked: Set<String> = []
        /// Extra free questions per topic from daily top-ups.
        var topUps: [String: Int] = [:]
        var lastOpenDay: Int?
        /// BuckleUp Basic's daily allowance used, and the day it was used.
        var basicDay: Int?
        var basicUsed = 0
        /// Pack purchases credited, by App Store transaction id (each counts once, everywhere).
        var creditedTransactions: Set<UInt64> = []
        /// Pack questions used so far, all time.
        var packUsed = 0

        var packsBought: Int { creditedTransactions.count }
        /// Bought questions not used yet.
        var packCredits: Int { max(0, packsBought * AllowanceStore.packSize - packUsed) }

        init() {}

        private enum CodingKeys: String, CodingKey {
            case unlocked, topUps, lastOpenDay, basicDay, basicUsed, creditedTransactions, packUsed
        }

        /// Key by key, so a backup from another build version never fails to load.
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            unlocked = (try? c.decodeIfPresent(Set<String>.self, forKey: .unlocked)) ?? []
            topUps = (try? c.decodeIfPresent([String: Int].self, forKey: .topUps)) ?? [:]
            lastOpenDay = try? c.decodeIfPresent(Int.self, forKey: .lastOpenDay)
            basicDay = try? c.decodeIfPresent(Int.self, forKey: .basicDay)
            basicUsed = (try? c.decodeIfPresent(Int.self, forKey: .basicUsed)) ?? 0
            creditedTransactions = (try? c.decodeIfPresent(Set<UInt64>.self, forKey: .creditedTransactions)) ?? []
            packUsed = (try? c.decodeIfPresent(Int.self, forKey: .packUsed)) ?? 0
        }

        /// Combines two copies: unions and maxima, never less than either.
        func merged(with other: State) -> State {
            var m = self
            m.unlocked.formUnion(other.unlocked)
            m.topUps.merge(other.topUps, uniquingKeysWith: max)
            m.lastOpenDay = [lastOpenDay, other.lastOpenDay].compactMap { $0 }.max()
            switch (basicDay, other.basicDay) {
            case let (a?, b?) where a == b: m.basicUsed = max(basicUsed, other.basicUsed)
            case let (a?, b?) where b > a: (m.basicDay, m.basicUsed) = (b, other.basicUsed)
            case (nil, _?): (m.basicDay, m.basicUsed) = (other.basicDay, other.basicUsed)
            default: break
            }
            m.creditedTransactions.formUnion(other.creditedTransactions)
            m.packUsed = max(packUsed, other.packUsed)
            return m
        }
    }

    /// Called after any change, so the backup (iCloud and Keychain) stays current.
    @ObservationIgnored var onChange: (() -> Void)?

    /// Brings in a copy from iCloud, the Keychain or another device.
    func merge(_ other: State) {
        state = state.merged(with: other)
    }

    private(set) var state: State {
        didSet {
            if state != oldValue {
                save()
                onChange?()
            }
        }
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
        next.packUsed += min(shared, next.packCredits)
        state = next
    }

    /// A question pack was bought. Returns false if this transaction was already credited.
    @discardableResult
    func creditPack(transactionID: UInt64) -> Bool {
        guard !state.creditedTransactions.contains(transactionID) else { return false }
        state.creditedTransactions.insert(transactionID)
        return true
    }

    private func saturatingAdd(_ a: Int, _ b: Int) -> Int {
        let (sum, overflow) = a.addingReportingOverflow(b)
        return overflow ? .max : sum
    }
}

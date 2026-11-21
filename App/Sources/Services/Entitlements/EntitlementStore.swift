import Foundation
import Observation
import QuizCore
import StoreKit

/// What the family has unlocked (ADR-0022).
///
/// - **Free:** the free topics (Animals, Geography, and Manners & Friendship with fewer
///   questions), up to 2 players per game, a set number of new questions (`AllowanceStore`).
/// - **BuckleUp Basic** (monthly subscription, cancel anytime): every topic, up to 6 players,
///   40 new questions a day and fixing scores after a game.
@MainActor
@Observable
final class EntitlementStore {
    /// Players who can play together without BuckleUp Basic.
    static let freePlayersPerGame = 2

    /// BuckleUp Basic is active (from StoreKit).
    var subscribed: Bool
    /// TestFlight and debug builds, where testers can switch Basic on without paying.
    private(set) var isTestBuild = false
    var testerUnlock: Bool {
        didSet { defaults.set(testerUnlock, forKey: Self.testerUnlockKey) }
    }

    private let defaults: UserDefaults
    private static let testerUnlockKey = "entitlements.testerUnlock"

    init(hasBasic: Bool = false, defaults: UserDefaults = .standard) {
        subscribed = hasBasic
        self.defaults = defaults
        testerUnlock = defaults.bool(forKey: Self.testerUnlockKey)
    }

    var hasBasic: Bool { subscribed || (isTestBuild && testerUnlock) }

    func isUnlocked(_ topic: Topic) -> Bool { topic.isFree || hasBasic }

    /// How many players can play in one game.
    var playersPerGame: Int { hasBasic ? PlayerStore.maxPlayers : Self.freePlayersPerGame }

    /// Fixing scores after a game is part of BuckleUp Basic.
    var canFixScores: Bool { hasBasic }

    /// Checks whether this is a TestFlight (sandbox) or debug build.
    func detectTestBuild() async {
        #if DEBUG
        isTestBuild = true
        #else
        if case .verified(let transaction)? = try? await AppTransaction.shared {
            isTestBuild = transaction.environment != .production
        }
        #endif
    }
}

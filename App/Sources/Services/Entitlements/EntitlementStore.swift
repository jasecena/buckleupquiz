import Foundation
import Observation
import QuizCore
import StoreKit

/// What the user has unlocked. Free tier: topics marked `isFree`, fixed-length sessions and up
/// to 2 players per game. The Family Pass unlocks everything, including games with up to 6
/// players. M6 replaces `purchased` with StoreKit 2 `Transaction.currentEntitlements` (ADR-0010).
@MainActor
@Observable
final class EntitlementStore {
    /// Players who can play together without the Family Pass.
    static let freePlayersPerGame = 2

    private(set) var purchased: Bool
    /// TestFlight and debug builds, where testers can switch the Family Pass on until real
    /// purchases arrive in M6.
    private(set) var isTestBuild = false
    var testerUnlock: Bool {
        didSet { defaults.set(testerUnlock, forKey: Self.testerUnlockKey) }
    }

    private let defaults: UserDefaults
    private static let testerUnlockKey = "entitlements.testerUnlock"

    init(hasFamilyPass: Bool = false, defaults: UserDefaults = .standard) {
        purchased = hasFamilyPass
        self.defaults = defaults
        testerUnlock = defaults.bool(forKey: Self.testerUnlockKey)
    }

    var hasFamilyPass: Bool { purchased || (isTestBuild && testerUnlock) }

    func isUnlocked(_ topic: Topic) -> Bool { topic.isFree || hasFamilyPass }

    func isAvailable(_ length: SessionLength) -> Bool { length != .endless || hasFamilyPass }

    /// How many players can play in one game.
    var playersPerGame: Int { hasFamilyPass ? PlayerStore.maxPlayers : Self.freePlayersPerGame }

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

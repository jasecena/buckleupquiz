import Observation
import QuizCore

/// What the user has unlocked. Free tier: topics marked `isFree`, fixed-length sessions.
/// M6 replaces the stored flag with StoreKit 2 `Transaction.currentEntitlements` (ADR-0010).
@MainActor
@Observable
final class EntitlementStore {
    private(set) var hasFamilyPass: Bool

    init(hasFamilyPass: Bool = false) {
        self.hasFamilyPass = hasFamilyPass
    }

    func isUnlocked(_ topic: Topic) -> Bool { topic.isFree || hasFamilyPass }

    func isAvailable(_ length: SessionLength) -> Bool { length != .endless || hasFamilyPass }
}

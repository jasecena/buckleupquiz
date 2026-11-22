import Foundation
import QuizCore
import Testing
@testable import BuckleUpQuiz

@MainActor
final class MemoryStorage: BackupStorage {
    var data: Data?
    func read() -> Data? { data }
    func write(_ data: Data) { self.data = data }
    func erase() { data = nil }
}

@MainActor
@Suite("Progress sync")
struct ProgressSyncTests {
    func freshStores() -> (AllowanceStore, PlayerStore) {
        (AllowanceStore(defaults: UserDefaults(suiteName: "sync-\(UUID())")!), PlayerStore.inMemory())
    }

    @Test func reinstallingBringsEverythingBack() throws {
        let keychain = MemoryStorage()
        let (allowance, players) = freshStores()
        let mia = try #require(players.add(name: "Mia", age: 7))
        var record = LearningRecord()
        record.record(.correct, for: "ani-0001", on: 10)
        players.recordLearning([mia.id.uuidString: record])
        allowance.charge(["ani-0001": .topic, "ani-0002": .shared], hasBasic: false, day: 10)
        allowance.creditPack(transactionID: 42)
        ProgressSync(allowance: allowance, players: players, storages: [keychain]).save()

        // The app is deleted and installed again: empty stores, but the Keychain copy is still there.
        let (newAllowance, newPlayers) = freshStores()
        ProgressSync(allowance: newAllowance, players: newPlayers, storages: [keychain]).restore()
        #expect(newPlayers.players.map(\.name) == ["Mia"])
        #expect(newPlayers.players.first?.id == mia.id)
        #expect(newPlayers.players.first?.learning.card("ani-0001")?.box == 2)
        #expect(newAllowance.state.unlocked.isSuperset(of: ["ani-0001", "ani-0002"]), "no free questions twice")
        #expect(newAllowance.state.packCredits == 50)
    }

    @Test func testerResetDoesNotComeBackAfterAReinstall() throws {
        let keychain = MemoryStorage()
        let (allowance, players) = freshStores()
        players.add(name: "Mia", age: 7)
        allowance.charge(["ani-0001": .topic], hasBasic: false, day: 10)
        let sync = ProgressSync(allowance: allowance, players: players, storages: [keychain])
        sync.save()

        sync.eraseBackup()
        players.eraseAll()
        allowance.reset()
        #expect(players.players.isEmpty)
        #expect(allowance.state.unlocked.isEmpty)
        #expect(keychain.data == nil)

        let (newAllowance, newPlayers) = freshStores()
        ProgressSync(allowance: newAllowance, players: newPlayers, storages: [keychain]).restore()
        #expect(newPlayers.players.isEmpty, "nothing to bring back")
    }

    @Test func twoCopiesMergeWithoutLosingAnything() {
        var phone = AllowanceStore.State()
        phone.unlocked = ["a", "b"]
        phone.creditedTransactions = [1]
        phone.packUsed = 10
        var cloud = AllowanceStore.State()
        cloud.unlocked = ["c"]
        cloud.creditedTransactions = [1, 2]
        cloud.packUsed = 5
        let merged = phone.merged(with: cloud)
        #expect(merged.unlocked == ["a", "b", "c"])
        #expect(merged.packsBought == 2)
        #expect(merged.packCredits == 90, "100 bought, the larger usage (10) kept")
    }

    @Test func aRenameIsKeptAndNobodyIsDuplicated() throws {
        let storage = MemoryStorage()
        let (allowance, players) = freshStores()
        let leo = try #require(players.add(name: "Leo", age: 9))
        let sync = ProgressSync(allowance: allowance, players: players, storages: [storage])
        sync.save()
        players.update(leo, name: "Leonardo", age: 9, colorHex: leo.colorHex)
        sync.save()
        sync.restore()
        #expect(players.players.map(\.name) == ["Leonardo"])
    }
}

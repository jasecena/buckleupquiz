@testable import BuckleUpQuiz
import Foundation
import QuizCore
import Testing

@MainActor
@Suite("Player store")
struct PlayerStoreTests {
    @Test func addsPlayersWithDistinctColours() throws {
        let store = PlayerStore.inMemory()
        let mia = try #require(store.add(name: "  Mia ", age: 7))
        let leo = try #require(store.add(name: "Leo", age: 11))
        #expect(store.players.map(\.name) == ["Mia", "Leo"])
        #expect(mia.colorHex != leo.colorHex)
        #expect(mia.ageBand == .sixToEight)
        #expect(leo.quizPlayer.ageBand == .elevenToTwelve)
    }

    @Test func rejectsBlankNamesAndCapsAtSix() {
        let store = PlayerStore.inMemory()
        #expect(store.add(name: "   ", age: 7) == nil)
        for i in 0..<PlayerStore.maxPlayers { store.add(name: "Kid \(i)", age: 8) }
        #expect(!store.canAddMore)
        #expect(store.add(name: "One more", age: 8) == nil)
        #expect(store.players.count == PlayerStore.maxPlayers)
    }

    @Test func ageGrowsWithTime() {
        let profile = PlayerProfile(name: "Mia", age: 8, colorHex: "#000000",
                                    now: Date(timeIntervalSince1970: 0))
        let twoYearsLater = Date(timeIntervalSince1970: 2 * 366 * 24 * 3600)
        #expect(profile.currentAge(now: twoYearsLater) == 10)
        #expect(AgeBand(age: profile.currentAge(now: twoYearsLater)) == .nineToTen)
    }

    @Test func updatesAndDeletes() throws {
        let store = PlayerStore.inMemory()
        let mia = try #require(store.add(name: "Mia", age: 7))
        store.update(mia, name: "Mia R", age: 9, colorHex: "#00B894")
        #expect(mia.name == "Mia R")
        #expect(mia.currentAge() == 9)
        store.delete(mia)
        #expect(store.players.isEmpty)
    }

    @Test func remembersEachPlayersBoxes() throws {
        let store = PlayerStore.inMemory()
        let mia = try #require(store.add(name: "Mia", age: 7))
        let leo = try #require(store.add(name: "Leo", age: 11))
        var first = LearningRecord()
        first.record(.correct, for: "ani-0001", on: 10)
        store.recordLearning([mia.id.uuidString: first])
        var second = store.learning(for: [mia])[mia.id.uuidString] ?? LearningRecord()
        second.record(.incorrect, for: "ani-0001", on: 11)
        second.record(.correct, for: "ani-0002", on: 11)
        store.recordLearning([mia.id.uuidString: second])

        let saved = store.learning(for: [mia, leo])
        #expect(saved[mia.id.uuidString]?.card("ani-0001") == ReviewCard(box: 1, due: 11))
        #expect(saved[mia.id.uuidString]?.card("ani-0002") == ReviewCard(box: 2, due: 12, last: 11))
        #expect(saved[leo.id.uuidString]?.cards.isEmpty == true, "Leo's boxes are his own")
    }

    @Test func settingsFromAnOlderBuildKeepTheirValues() throws {
        let json = #"{"speechRate": 0.6, "lastAgeBand": "9-10", "duckOthers": false}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.speechRate == 0.6)
        #expect(settings.duckOthers == false)
        #expect(settings.selectedPlayerIDs.isEmpty)
    }

    @Test func oldDefaultThinkTimeMovesTo6SecondsOnce() throws {
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"listen": {"thinkTime": 8}}"#.utf8))
        #expect(old.listen.thinkTime == 6)
        let chosen = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"listen": {"thinkTime": 12}}"#.utf8))
        #expect(chosen.listen.thinkTime == 12)
        var picked8 = AppSettings()
        picked8.listen.thinkTime = 8
        let resaved = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(picked8))
        #expect(resaved.listen.thinkTime == 8, "a parent who picks 8 again keeps it")
    }

    @Test @MainActor func freeGamesHaveTwoPlayersAndTheFamilyPassSix() {
        #expect(EntitlementStore().playersPerGame == 2)
        #expect(EntitlementStore(hasBasic: true).playersPerGame == 6)
    }
}

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

    @Test func remembersSeenQuestions() throws {
        let store = PlayerStore.inMemory()
        let mia = try #require(store.add(name: "Mia", age: 7))
        let id = mia.id.uuidString
        store.recordSeen([id: ["ani-0001", "ani-0002"]])
        store.recordSeen([id: ["ani-0002", "ani-0003"]])
        #expect(store.seenQuestionIDs(for: [mia])[id] == ["ani-0001", "ani-0002", "ani-0003"])
    }

    @Test func settingsFromAnOlderBuildKeepTheirValues() throws {
        let json = #"{"speechRate": 0.6, "lastAgeBand": "9-10", "duckOthers": false}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.speechRate == 0.6)
        #expect(settings.duckOthers == false)
        #expect(settings.selectedPlayerIDs.isEmpty)
    }
}

import Testing
@testable import QuizCore

@Suite("Scoring")
struct ScoringTests {
    @Test func streakBonusStartsOnThirdCorrect() {
        var keeper = ScoreKeeper()
        let awarded = (1...5).map { _ in keeper.record(.correct, playerID: "mia", topic: "space").pointsAwarded }
        #expect(awarded == [10, 10, 15, 15, 15])
        #expect(keeper.stats(for: "mia").points == 65)
        #expect(keeper.stats(for: "mia").bestStreak == 5)
    }

    @Test func wrongAnswerResetsStreak() {
        var keeper = ScoreKeeper()
        for _ in 0..<3 { keeper.record(.correct, playerID: "leo", topic: "space") }
        keeper.record(.timedOut, playerID: "leo", topic: "space")
        let next = keeper.record(.correct, playerID: "leo", topic: "space")
        #expect(next.pointsAwarded == 10)
        #expect(next.streak == 1)
        let stats = keeper.stats(for: "leo")
        #expect(stats.bestStreak == 3)
        #expect(stats.attempted == 5)
        #expect(stats.correct == 4)
        #expect(stats.byTopic["space"] == TopicStats(correct: 4, attempted: 5))
    }

    @Test func skipsAndTalkAboutDoNotCountAsAttempts() {
        var keeper = ScoreKeeper()
        keeper.record(.correct, playerID: "p", topic: "t")
        keeper.record(.notScored, playerID: "p", topic: "t")
        #expect(keeper.stats(for: "p").currentStreak == 1)
        keeper.record(.skipped, playerID: "p", topic: "t")
        #expect(keeper.stats(for: "p").currentStreak == 0)
        #expect(keeper.stats(for: "p").attempted == 1)
    }

    @Test func scoreboardRanksWithTies() {
        let mia = Player(id: "mia", name: "Mia", ageBand: .sixToEight)
        let leo = Player(id: "leo", name: "Leo", ageBand: .nineToTen)
        let sam = Player(id: "sam", name: "Sam", ageBand: .elevenToTwelve)
        var keeper = ScoreKeeper()
        keeper.record(.correct, playerID: "leo", topic: "t")
        keeper.record(.correct, playerID: "sam", topic: "t")
        let board = Scoreboard.rank(players: [mia, leo, sam], scores: keeper)
        #expect(board.map(\.player.name) == ["Leo", "Sam", "Mia"])
        #expect(board.map(\.rank) == [1, 1, 3])
        #expect(Phrases.scoreAnnouncement(board)
            == "That's the end of the ride! Here are the scores… It's a tie! Leo and Sam both got 10 points! Mia got 0 points!")
    }

    @Test func announcesWinner() {
        let mia = Player(id: "mia", name: "Mia", ageBand: .sixToEight)
        let leo = Player(id: "leo", name: "Leo", ageBand: .nineToTen)
        var keeper = ScoreKeeper()
        for _ in 0..<2 { keeper.record(.correct, playerID: "mia", topic: "t") }
        keeper.record(.correct, playerID: "leo", topic: "t")
        let text = Phrases.scoreAnnouncement(Scoreboard.rank(players: [mia, leo], scores: keeper))
        #expect(text == "That's the end of the ride! Here are the scores… Mia wins with 20 points! Leo got 10 points!")
    }

    @Test func badges() {
        var stats = PlayerStats()
        stats.bestStreak = 10
        stats.byTopic["space"] = TopicStats(correct: 9, attempted: 10)
        stats.byTopic["maths"] = TopicStats(correct: 7, attempted: 10)
        let topics = ["space", "maths"].map {
            Topic(id: $0, name: $0.capitalized, symbol: "s", color: "#000000", category: .knowledge, isFree: true)
        }
        let ids = BadgeRules.earned(by: stats, topics: topics).map(\.id)
        #expect(ids == ["streak-5", "streak-10", "expert-space"])
    }
}

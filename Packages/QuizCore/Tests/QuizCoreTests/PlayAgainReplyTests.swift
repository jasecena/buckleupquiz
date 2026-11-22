import Testing
@testable import QuizCore

/// "Just say new game" at the end of a voice game (`PlayAgainReply`).
@Suite("Play again by voice")
struct PlayAgainReplyTests {
    @Test(arguments: ["New game", "new game!", "Play again", "Again!", "One more", "Another one",
                      "More!", "Yes please", "Let's play", "Start a new game", "Can we have another game?",
                      "Keep going"])
    func clearAsksStartANewGame(_ said: String) {
        #expect(PlayAgainReply.parse([said]) == .newGame)
    }

    @Test(arguments: ["No", "No more", "No thanks", "Not now", "Stop", "We're done", "Nope", "That's enough"])
    func noAlwaysWins(_ said: String) {
        #expect(PlayAgainReply.parse([said]) == .noThanks)
    }

    @Test(arguments: ["Yes!", "Yes, I won!", "Okay", "Umm", "Mum, look at the cows", ""])
    func cheersAndChatterDoNothing(_ said: String) {
        #expect(PlayAgainReply.parse([said]) == nil)
    }

    @Test func longChatterIsIgnoredEvenWithTheWords() {
        #expect(PlayAgainReply.parse(["and then we went to the shop again and bought some more bread"]) == nil)
    }

    @Test func anyAlternativeCanCarryTheReply() {
        #expect(PlayAgainReply.parse(["knew gain", "new game"]) == .newGame)
        #expect(PlayAgainReply.parse(["new game", "no game"]) == .noThanks, "a no anywhere is a no")
        #expect(PlayAgainReply.parse([]) == nil)
    }
}

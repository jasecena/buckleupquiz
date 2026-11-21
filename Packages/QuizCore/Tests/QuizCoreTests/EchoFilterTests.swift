import Testing
@testable import QuizCore

@Suite("Echo filter")
struct EchoFilterTests {
    let options = "A: Hobart. B: Launceston. C: Darwin."

    @Test func theAppsOwnVoiceIsRemoved() {
        #expect(EchoFilter.remove(options, from: "a hobart b launceston c darwin") == "")
    }

    @Test func anAnswerShoutedOverTheOptionsIsKept() {
        #expect(EchoFilter.remove(options, from: "a hobart hobart b launceston c darwin") == "hobart")
        #expect(EchoFilter.remove(options, from: "a hobart b b launceston c darwin") == "b")
        #expect(EchoFilter.remove(options, from: "a hobart b launceston c darwin it's hobart") == "its hobart")
    }

    @Test func anEarlyAnswerBeforeTheAppSaysItStillCounts() {
        // The child says "Hobart" first; the app's "hobart" then has nothing to cancel.
        #expect(EchoFilter.remove(options, from: "hobart a hobart b launceston c darwin") == "hobart")
        #expect(EchoFilter.remove(options, from: "darwin a hobart b launceston c") == "darwin")
    }

    @Test func misheardEchoAndTheQuestionsTailAreHandled() {
        #expect(EchoFilter.remove(options, from: "a hobert b lonceston c darwin") == "")
        #expect(EchoFilter.remove("of Tasmania? " + options, from: "tasmania a hobart b launceston c darwin b") == "b")
    }

    @Test func cleanedRepliesAreJudgedNormally() {
        let q = present(makeQuestion(options: ["Hobart", "Launceston", "Darwin"], answer: "Hobart"))
        let heard = EchoFilter.remove(options, from: ["a hobart b launceston c darwin hobart"])
        #expect(VoiceReply.interpret(heard, for: q) == .answer(.correct, heard: "hobart"))
        let echoOnly = EchoFilter.remove(options, from: ["a hobart b launceston c darwin"])
        #expect(VoiceReply.interpret(echoOnly, for: q) == .silence)
    }
}

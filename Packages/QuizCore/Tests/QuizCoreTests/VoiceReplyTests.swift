import Testing
@testable import QuizCore

@Suite("Voice replies")
struct VoiceReplyTests {
    let tasmania = present(makeQuestion(options: ["Hobart", "Launceston", "Darwin"], answer: "Hobart"))

    @Test func rightAndWrongAnswers() {
        #expect(VoiceReply.interpret(["I think it's Hobart"], for: tasmania) == .answer(.correct, heard: "I think it's Hobart"))
        #expect(VoiceReply.interpret(["a"], for: tasmania) == .answer(.correct, heard: "a"))
        #expect(VoiceReply.interpret(["Darwin"], for: tasmania) == .answer(.incorrect, heard: "Darwin"))
    }

    @Test func anyAlternativeTranscriptionCounts() {
        #expect(VoiceReply.interpret(["hold it", "Hobart"], for: tasmania) == .answer(.correct, heard: "Hobart"))
    }

    @Test func commandsBeatAnswers() {
        #expect(VoiceReply.interpret(["skip"], for: tasmania) == .command(.skip))
        #expect(VoiceReply.interpret(["say it again"], for: tasmania) == .command(.repeat))
        #expect(VoiceReply.interpret(["we're done"], for: tasmania) == .command(.skip))
    }

    @Test func silenceAndMumbles() {
        #expect(VoiceReply.interpret([], for: tasmania) == .silence)
        #expect(VoiceReply.interpret(["", "  "], for: tasmania) == .silence)
        #expect(VoiceReply.interpret(["umm"], for: tasmania) == .garbled)
        #expect(VoiceReply.interpret(["hmm let me think"], for: tasmania) == .garbled)
    }

    @Test func chatterAndEchoAreNotWrongAnswers() {
        #expect(VoiceReply.interpret(["Mum can we stop"], for: tasmania) == .garbled)
        #expect(VoiceReply.interpret(["what is the capital of Tasmania"], for: tasmania) == .garbled)
        #expect(VoiceReply.interpret(["Hobart or Darwin"], for: tasmania) == .garbled, "a hedge isn't a wrong answer")
        #expect(!VoiceReply.garbled.isConclusive && !VoiceReply.silence.isConclusive)
        #expect(VoiceReply.interpret(["Darwin"], for: tasmania).isConclusive)
        #expect(VoiceReply.interpret(["next"], for: tasmania).isConclusive)
    }

    @Test func trueFalseByVoice() {
        let q = present(makeQuestion(type: .trueFalse, text: "Koalas are bears.", answer: "False"))
        #expect(VoiceReply.interpret(["no"], for: q) == .answer(.correct, heard: "no"))
        #expect(VoiceReply.interpret(["true"], for: q) == .answer(.incorrect, heard: "true"))
        #expect(VoiceReply.hints(for: q).contains("false"))
    }

    @Test func voiceStepsListenThenGiveFeedback() {
        let turn = Turn(number: 2, player: .listener(ageBand: .sixToEight), presented: tasmania)
        let steps = ListenScript.steps(for: turn, category: .knowledge, settings: ListenSettings(), addressPlayer: false,
                                       voiceAnswers: true)
        let listen = steps.firstIndex(of: .listen(seconds: 6, options: "A: Hobart. B: Launceston. C: Darwin."))
        #expect(!steps.contains { if case .say(_, .options) = $0 { true } else { false } },
                "options are read inside the listening step, so early answers are heard")
        let feedback = steps.firstIndex(of: .feedback)
        #expect(listen != nil && feedback != nil && listen! < feedback!)
        #expect(!steps.contains { if case .think = $0 { true } else { false } })
        #expect(!steps.contains { if case .say(_, .answer) = $0 { true } else { false } })
    }

    @Test func streaksAndBadgesAreCheered() {
        #expect(Phrases.streak(2) == nil)
        #expect(Phrases.streak(3) == "That's three in a row!")
        let badge = Badge(id: "streak-5", title: "High Five", detail: "")
        #expect(Phrases.badgeEarned(badge, by: Player(id: "m", name: "Mia", age: 7)) == "Mia earned the High Five badge!")
    }

    @Test func lifetimeStatsAddUp() {
        var lifetime = PlayerStats()
        lifetime.points = 50; lifetime.correct = 5; lifetime.attempted = 8; lifetime.bestStreak = 4
        lifetime.byTopic["space"] = TopicStats(correct: 3, attempted: 4)
        var session = PlayerStats()
        session.points = 25; session.correct = 2; session.attempted = 3; session.bestStreak = 2; session.currentStreak = 1
        session.byTopic["space"] = TopicStats(correct: 2, attempted: 3)
        let total = lifetime.adding(session)
        #expect(total.points == 75)
        #expect(total.correct == 7 && total.attempted == 11)
        #expect(total.bestStreak == 4)
        #expect(total.byTopic["space"] == TopicStats(correct: 5, attempted: 7))
    }
}

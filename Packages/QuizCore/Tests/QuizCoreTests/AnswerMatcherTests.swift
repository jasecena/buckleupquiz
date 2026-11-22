import Testing
@testable import QuizCore

/// Letters only (ADR-0026): "Correct!" is said only when the child names the right option's letter.
@Suite("Answer matching")
struct AnswerMatcherTests {
    let matcher = AnswerMatcher()

    func judge(_ heard: [String], _ q: Question) -> MatchOutcome {
        matcher.match(transcriptions: heard, to: present(q))
    }

    /// Hobart is option A.
    var tasmania: Question { makeQuestion(answer: "Hobart", accepted: ["hobart city"]) }

    // MARK: The letter

    @Test(arguments: ["A", "a", "A.", "A!", "Ay", "Aye", "Option A", "option a", "It's A", "I think it's A",
                      "I said A", "Yeah A", "Umm A", "answer A", "letter A"])
    func acceptsTheRightLetter(heard: String) {
        #expect(judge([heard], tasmania) == .correct(heard: heard))
    }

    @Test(arguments: ["B", "Bee", "option B", "C", "see", "I think it's C"])
    func otherLettersAreWrong(heard: String) {
        #expect(judge([heard], tasmania) == .incorrect(heard: heard))
    }

    @Test(arguments: ["B", "b", "Be", "Bee", "Bea", "Option B", "It's B"])
    func letterHomophones(heard: String) {
        let q = makeQuestion(answer: "Launceston")
        #expect(judge([heard], q) == .correct(heard: heard))
    }

    @Test func lettersFollowTheOptionsReadOut() {
        #expect(judge(["D"], tasmania) == .incorrect(heard: "D"), "there's no option D")
        var rng = SeededGenerator(seed: 42)
        let presented = PresentedQuestion(question: tasmania, shuffleOptions: true, using: &rng)
        let index = try! #require(presented.correctOptionIndex)
        #expect(presented.options?[index] == "Hobart")
        let letter = PresentedQuestion.letters[index]
        #expect(matcher.match(transcriptions: [letter], to: presented) == .correct(heard: letter))
    }

    // MARK: Words are never checked

    @Test(arguments: ["Hobart", "hobart city", "I think it's Hobart", "A Hobart", "Hobart A", "A, Hobart"])
    func theAnswersWordsDontCount(heard: String) {
        #expect(judge([heard], tasmania) == .incorrect(heard: heard))
    }

    @Test(arguments: ["A or B", "A B", "A, B, C", "not B", "Hey"])
    func moreThanALetterIsNotAnAnswer(heard: String) {
        #expect(judge([heard], tasmania) != .correct(heard: heard))
    }

    // MARK: The recogniser's guesses must agree

    @Test func agreeingGuessesCount() {
        #expect(judge(["A", "a", "aye"], tasmania) == .correct(heard: "A"))
        #expect(judge(["hey A", "A"], tasmania) == .correct(heard: "A"), "guesses that name no option are ignored")
    }

    @Test func disagreeingGuessesAreNeverRight() {
        #expect(judge(["B", "A"], tasmania) == .incorrect(heard: "B"))
        #expect(judge(["A", "B"], tasmania) == .incorrect(heard: "A"))
        #expect(matcher.chosenOption(transcriptions: ["A", "B"], presented: present(tasmania)) == nil)
    }

    @Test func silenceIsNoAnswer() {
        #expect(judge([], tasmania) == .noAnswer)
        #expect(judge(["", "  ", "?!"], tasmania) == .noAnswer)
    }

    // MARK: True/false

    var angerOK: Question {
        makeQuestion(topic: "manners", type: .trueFalse,
                     text: "It's okay to feel angry, as long as we don't hurt anyone. True or false?",
                     answer: "True")
    }

    @Test(arguments: ["true", "True!", "it's true", "I think it's true"])
    func acceptsTrue(heard: String) {
        #expect(judge([heard], angerOK) == .correct(heard: heard))
    }

    @Test(arguments: ["false", "it's false", "not true", "true or false", "yes", "right", "A"])
    func onlyTheWordTrueIsRight(heard: String) {
        #expect(judge([heard], angerOK) == .incorrect(heard: heard))
    }

    @Test func talkAboutIsNeverCorrect() {
        let q = makeQuestion(type: .talkAbout, answer: nil)
        #expect(judge(["my friend shared lunch"], q) == .incorrect(heard: "my friend shared lunch"))
    }

    // MARK: Voice commands

    @Test func parsesVoiceCommands() {
        #expect(VoiceCommand.parse(["Skip!"]) == .skip)
        #expect(VoiceCommand.parse(["next"]) == .skip)
        #expect(VoiceCommand.parse(["say it again"]) == .repeat)
        #expect(VoiceCommand.parse(["stop"]) == .stop)
        #expect(VoiceCommand.parse(["Hobart"]) == nil)
        #expect(VoiceCommand.parse(["stop the car"]) == nil)
    }
}

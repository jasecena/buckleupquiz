import Testing
@testable import QuizCore

@Suite("Answer matching")
struct AnswerMatcherTests {
    let matcher = AnswerMatcher()

    func judge(_ heard: [String], _ q: Question) -> MatchOutcome {
        matcher.match(transcriptions: heard, to: present(q))
    }

    // MARK: Saying the option text instead of the letter

    var tasmania: Question { makeQuestion(answer: "Hobart", accepted: ["hobart city"]) }

    @Test(arguments: ["Hobart", "hobart.", "The Hobart", "Hobert", "hobart city", "I think it's Hobart", "A", "option A"])
    func acceptsOptionTextVariants(heard: String) {
        #expect(judge([heard], tasmania) == .correct(heard: heard))
    }

    @Test(arguments: ["Launceston", "Darwin", "Melbourne", "Ho", "Hobart or Darwin", "B", "D"])
    func rejectsWrongOptions(heard: String) {
        #expect(judge([heard], tasmania) == .incorrect(heard: heard))
    }

    @Test func numbersMatchWordsAndDigits() {
        let q = makeQuestion(options: ["20", "21", "22"], answer: "21")
        for heard in ["twenty one", "twenty-one", "21", "B"] {
            #expect(judge([heard], q) == .correct(heard: heard), "\(heard)")
        }
        let seven = makeQuestion(options: ["six", "seven", "eight"], answer: "seven")
        #expect(judge(["7"], seven) == .correct(heard: "7"))
    }

    @Test func numbersAreNeverFuzzy() {
        let q = makeQuestion(options: ["20", "21", "22"], answer: "21")
        #expect(judge(["22"], q) == .incorrect(heard: "22"))
        #expect(judge(["twenty two"], q) == .incorrect(heard: "twenty two"))
        #expect(judge(["23"], q) == .incorrect(heard: "23"))
    }

    @Test func shortWordsMustBeExact() {
        let q = makeQuestion(options: ["cat", "bat", "dog"], answer: "cat")
        #expect(judge(["bat"], q) == .incorrect(heard: "bat"))
        #expect(judge(["cap"], q) == .incorrect(heard: "cap"))
        #expect(judge(["cat"], q) == .correct(heard: "cat"))
    }

    @Test func longWordsAllowTwoEdits() {
        let q = makeQuestion(options: ["Kookaburra", "Cockatoo", "Magpie"], answer: "Kookaburra")
        #expect(judge(["cookaburra"], q) == .correct(heard: "cookaburra"))
        #expect(judge(["kookaburro"], q) == .correct(heard: "kookaburro"))
        #expect(judge(["cockatoo"], q) == .incorrect(heard: "cockatoo"))
    }

    @Test func anyAlternativeTranscriptionCounts() {
        #expect(judge(["low bat", "hobart"], tasmania) == .correct(heard: "hobart"))
    }

    @Test func silenceIsNoAnswer() {
        #expect(judge([], makeQuestion()) == .noAnswer)
        #expect(judge(["", "  ", "?!"], makeQuestion()) == .noAnswer)
    }

    // MARK: Multiple choice

    var ocean: Question {
        makeQuestion(type: .multipleChoice, options: ["Indian", "Pacific", "Atlantic"], answer: "Pacific")
    }

    @Test(arguments: ["B", "b", "option B", "Option bee", "I think it's B", "Pacific", "the pacific", "pacific ocean"])
    func acceptsChoiceByLetterOrText(heard: String) {
        var q = ocean
        q.acceptedAnswers = ["pacific ocean"]
        #expect(judge([heard], q) == .correct(heard: heard))
    }

    @Test(arguments: ["A", "option C", "Atlantic", "Pacific or Atlantic", "E"])
    func rejectsWrongOrHedgedChoices(heard: String) {
        #expect(judge([heard], ocean) == .incorrect(heard: heard))
    }

    @Test func letterFollowsShuffledOrder() {
        var rng = SeededGenerator(seed: 42)
        let presented = PresentedQuestion(question: ocean, shuffleOptions: true, using: &rng)
        let index = try! #require(presented.correctOptionIndex)
        #expect(presented.options?[index] == "Pacific")
        let letter = PresentedQuestion.letters[index]
        #expect(matcher.match(transcriptions: [letter], to: presented) == .correct(heard: letter))
    }

    // MARK: Scenario

    var kindness: Question {
        makeQuestion(
            topic: "manners", type: .scenario,
            options: ["Laugh", "Help them up and ask if they're okay", "Keep playing"],
            answer: "Help them up and ask if they're okay")
    }

    @Test(arguments: ["B", "help them up", "help them up and ask if they're okay", "ask if they are okay"])
    func acceptsScenarioParaphrase(heard: String) {
        #expect(judge([heard], kindness) == .correct(heard: heard))
    }

    @Test(arguments: ["laugh", "keep playing", "C"])
    func rejectsUnkindScenarioChoices(heard: String) {
        #expect(judge([heard], kindness) == .incorrect(heard: heard))
    }

    // MARK: True/false

    var angerOK: Question {
        makeQuestion(topic: "manners", type: .trueFalse,
                     text: "It's okay to feel angry, as long as we don't hurt anyone. True or false?",
                     answer: "True")
    }

    @Test(arguments: ["true", "True!", "yes", "it's true"])
    func acceptsTrue(heard: String) {
        #expect(judge([heard], angerOK) == .correct(heard: heard))
    }

    @Test(arguments: ["false", "no", "not true", "true or false", "A"])
    func rejectsFalseOrHedge(heard: String) {
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

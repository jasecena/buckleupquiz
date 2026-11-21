#if DEBUG
import QuizCore

extension QuestionBank {
    /// Small bank for SwiftUI previews.
    static let preview = QuestionBank(
        topics: [
            Topic(id: "animals", name: "Animals", symbol: "pawprint.fill", color: "#F39C12", category: .knowledge, isFree: true),
            Topic(id: "space", name: "Space", symbol: "moon.stars.fill", color: "#6C5CE7", category: .knowledge, isFree: false),
        ],
        questions: [
            Question(id: "ani-0001", topic: "animals", ageBand: .sixToEight, type: .open,
                     question: "What is a baby kangaroo called?", answer: "Joey", acceptedAnswers: ["joey"]),
            Question(id: "spc-0001", topic: "space", ageBand: .sixToEight, type: .open,
                     question: "What is the closest star to Earth?", answer: "The Sun", acceptedAnswers: ["sun"]),
        ]
    )
}
#endif

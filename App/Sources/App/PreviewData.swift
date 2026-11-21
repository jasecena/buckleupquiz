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
            Question(id: "ani-0001", topic: "animals", ageBand: .sixToEight, type: .multipleChoice,
                     question: "What is a baby kangaroo called?", options: ["Joey", "Cub", "Chick"], answer: "Joey"),
            Question(id: "spc-0001", topic: "space", ageBand: .sixToEight, type: .multipleChoice,
                     question: "What is the closest star to Earth?", options: ["The Moon", "The Sun", "The North Star"],
                     answer: "The Sun"),
        ]
    )
}
#endif

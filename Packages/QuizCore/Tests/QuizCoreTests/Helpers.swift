import Foundation
@testable import QuizCore

func makeQuestion(
    _ id: String = "q-1", topic: String = "geography", band: AgeBand = .sixToEight,
    type: QuestionType = .open, text: String = "Question?", options: [String]? = nil,
    answer: String? = "Hobart", accepted: [String] = [], minAge: Int? = nil
) -> Question {
    Question(id: id, topic: topic, ageBand: band, type: type, question: text, options: options,
             answer: answer, acceptedAnswers: accepted, minAge: minAge)
}

/// Presents without shuffling so option letters are predictable.
func present(_ q: Question) -> PresentedQuestion {
    var rng = SeededGenerator(seed: 1)
    return PresentedQuestion(question: q, shuffleOptions: false, using: &rng)
}

func fixtureContentURL() -> URL {
    Bundle.module.url(forResource: "Fixtures", withExtension: nil)!.appendingPathComponent("Content")
}

func sampleBank(perBand: Int = 5, topics: [String] = ["geography"]) -> QuestionBank {
    let topicModels = topics.map {
        Topic(id: $0, name: $0.capitalized, symbol: "star", color: "#000000", category: .knowledge, isFree: true)
    }
    var questions: [Question] = []
    for topic in topics {
        for band in AgeBand.allCases {
            for i in 0..<perBand {
                questions.append(makeQuestion("\(topic)-\(band.rawValue)-\(i)", topic: topic, band: band))
            }
        }
    }
    return QuestionBank(topics: topicModels, questions: questions)
}

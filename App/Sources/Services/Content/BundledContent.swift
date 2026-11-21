import Foundation
import QuizCore

/// The question bank shipped inside the app (ADR-0006). A downloadable content-pack
/// source can replace this later without touching the UI (ADR-0012).
enum BundledContent {
    static func source(bundle: Bundle = .main) -> any QuestionSource {
        guard let root = bundle.url(forResource: "Content", withExtension: nil) else {
            return InMemoryQuestionSource(bank: .empty)
        }
        return DirectoryQuestionSource(root: root)
    }
}

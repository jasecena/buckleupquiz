import Foundation
import QuizCore

/// The question bank shipped inside the app (ADR-0006), or a newer downloaded set (ADR-0031)
/// with the bundled one as its fallback.
enum BundledContent {
    static func source(bundle: Bundle = .main) -> any QuestionSource {
        guard let root = bundle.url(forResource: "Content", withExtension: nil) else {
            return InMemoryQuestionSource(bank: .empty)
        }
        return DirectoryQuestionSource(root: root)
    }

    /// Plays from `downloaded` when there is one; if it can't be read, the bundled questions.
    static func source(downloaded: URL?, telemetry: Telemetry, bundle: Bundle = .main) -> any QuestionSource {
        let bundled = source(bundle: bundle)
        guard let downloaded else { return bundled }
        return FallbackQuestionSource(primary: DirectoryQuestionSource(root: downloaded), fallback: bundled,
                                      onFallback: { [weak telemetry] _ in
                                          await telemetry?.record("content.downloadedSetUnreadable", [:])
                                      })
    }
}

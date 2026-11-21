/// Removes the app's own voice from what the microphone heard (ADR-0018 amendment).
///
/// The app listens while it reads the options, because excited kids answer early. On a phone
/// speaker the microphone also hears the app ("A: Hobart. B: Launceston…"). Since we know exactly
/// what was said, those words are taken out in order and only what's left is judged: a child
/// shouting "Hobart!" over the options leaves "hobart".
public enum EchoFilter {
    /// `heard` with the words of `spoken` removed. Uses the longest in-order (fuzzy) alignment
    /// between the two, so an answer said before, during or after the echo is what's left.
    public static func remove(_ spoken: String, from heard: String) -> String {
        let reference = TextNormalizer.tokens(spoken)
        let words = TextNormalizer.tokens(heard)
        guard !reference.isEmpty, !words.isEmpty else { return words.joined(separator: " ") }
        let n = words.count, m = reference.count
        // Longest common subsequence table, with "similar" as equality.
        var table = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                table[i][j] = similar(words[i], reference[j])
                    ? table[i + 1][j + 1] + 1
                    : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var echo = Set<Int>()
        var i = 0, j = 0
        while i < n, j < m {
            if similar(words[i], reference[j]), table[i][j] == table[i + 1][j + 1] + 1 {
                echo.insert(i)
                i += 1
                j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return words.indices.filter { !echo.contains($0) }.map { words[$0] }.joined(separator: " ")
    }

    /// Every alternative transcription, cleaned.
    public static func remove(_ spoken: String, from transcriptions: [String]) -> [String] {
        transcriptions.map { remove(spoken, from: $0) }
    }

    /// Same word, allowing the recogniser's usual slips (as answer matching does).
    static func similar(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let allowed = Levenshtein.threshold(forLength: max(a.count, b.count))
        guard allowed > 0, !a.contains(where: \.isNumber), !b.contains(where: \.isNumber) else { return false }
        return Levenshtein.distance(a, b) <= allowed
    }
}

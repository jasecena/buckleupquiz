import Foundation

/// Normalises spoken/written text for comparison (FEATURES §3.4):
/// lowercase, fold accents, strip punctuation, drop articles, number words → digits.
public enum TextNormalizer {
    public static let articles: Set<String> = ["the", "a", "an"]

    /// Lowercased, accent-folded, punctuation-free tokens. Articles and number words are kept,
    /// so callers that care about "A" (an option letter) can still see it.
    public static func tokens(_ text: String) -> [String] {
        let folded = text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_AU"))
            .lowercased()
        let chars = Array(folded)
        var out = ""
        out.reserveCapacity(chars.count)
        for (i, c) in chars.enumerated() {
            if c.isLetter || c.isNumber {
                out.append(c)
                continue
            }
            let prevIsDigit = i > 0 && chars[i - 1].isNumber
            let nextIsDigit = i + 1 < chars.count && chars[i + 1].isNumber
            switch c {
            case "'", "’", "‘", "`":
                continue // "don't" -> "dont"
            case "," where prevIsDigit && nextIsDigit:
                continue // "1,000" -> "1000"
            case "." where prevIsDigit && nextIsDigit:
                out.append(".") // keep decimals
            case "&":
                out.append(" and ")
            case "%":
                out.append(" percent ")
            default:
                out.append(" ")
            }
        }
        return out.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Fully normalised tokens: articles removed, number words converted to digits.
    public static func normalizedTokens(_ text: String) -> [String] {
        NumberWords.replacingNumberWords(in: tokens(text).filter { !articles.contains($0) })
    }

    /// Fully normalised string, e.g. "The Twenty-One Apples!" -> "21 apples".
    public static func normalize(_ text: String) -> String {
        normalizedTokens(text).joined(separator: " ")
    }
}

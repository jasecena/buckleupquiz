/// Converts English number words to digits ("twenty one" -> "21") and spells numbers for speech.
public enum NumberWords {
    enum Kind: Equatable { case unit, teen, ten, hundred, scale }

    private static let words: [String: (Kind, Int)] = {
        var map: [String: (Kind, Int)] = [:]
        let units = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
        for (v, w) in units.enumerated() { map[w] = (.unit, v) }
        let teens = ["ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen",
                     "sixteen", "seventeen", "eighteen", "nineteen"]
        for (i, w) in teens.enumerated() { map[w] = (.teen, 10 + i) }
        let tens = ["twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
        for (i, w) in tens.enumerated() { map[w] = (.ten, 20 + i * 10) }
        map["fourty"] = (.ten, 40) // common misspelling
        map["hundred"] = (.hundred, 100)
        map["thousand"] = (.scale, 1_000)
        map["million"] = (.scale, 1_000_000)
        return map
    }()

    private struct Parser {
        var total = 0
        var current = 0
        var last: Kind?
        var groupHasHundred = false
        var lastScale: Int?

        var value: Int { total + current }
        var canTakeAnd: Bool { last == .hundred || last == .scale }

        func accepts(_ kind: Kind, _ value: Int) -> Bool {
            let scaleOK = kind == .scale && (lastScale.map { value < $0 } ?? true)
            guard let last else { return true }
            switch last {
            case .unit, .teen:
                return (kind == .hundred && !groupHasHundred) || scaleOK
            case .ten:
                return kind == .unit || scaleOK
            case .hundred:
                return kind == .unit || kind == .teen || kind == .ten || scaleOK
            case .scale:
                return kind == .unit || kind == .teen || kind == .ten
            }
        }

        mutating func add(_ kind: Kind, _ value: Int) {
            switch kind {
            case .unit, .teen, .ten:
                current += value
            case .hundred:
                current = max(current, 1) * 100
                groupHasHundred = true
            case .scale:
                total += max(current, 1) * value
                current = 0
                groupHasHundred = false
                lastScale = value
            }
            last = kind
        }
    }

    /// Replaces runs of number words with a single digit token. Other tokens pass through.
    public static func replacingNumberWords(in tokens: [String]) -> [String] {
        var out: [String] = []
        var i = 0
        while i < tokens.count {
            guard words[tokens[i]] != nil else {
                out.append(tokens[i])
                i += 1
                continue
            }
            var parser = Parser()
            while i < tokens.count {
                let token = tokens[i]
                if token == "and", parser.canTakeAnd, i + 1 < tokens.count,
                   let (nextKind, _) = words[tokens[i + 1]],
                   nextKind == .unit || nextKind == .teen || nextKind == .ten {
                    i += 1
                    continue
                }
                guard let (kind, value) = words[token], parser.accepts(kind, value) else { break }
                parser.add(kind, value)
                i += 1
            }
            out.append(String(parser.value))
        }
        return out
    }

    /// Spells 0...999_999 in words, e.g. 21 -> "twenty-one". Larger numbers fall back to digits.
    public static func spell(_ n: Int) -> String {
        let units = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
                     "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
                     "seventeen", "eighteen", "nineteen"]
        let tens = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
        func below1000(_ n: Int) -> String {
            var parts: [String] = []
            if n >= 100 { parts.append("\(units[n / 100]) hundred") }
            let rest = n % 100
            if rest > 0 {
                if n >= 100 { parts.append("and") }
                if rest < 20 { parts.append(units[rest]) }
                else { parts.append(tens[rest / 10] + (rest % 10 > 0 ? "-\(units[rest % 10])" : "")) }
            }
            return parts.joined(separator: " ")
        }
        guard (0..<1_000_000).contains(n) else { return String(n) }
        if n == 0 { return "zero" }
        if n < 1000 { return below1000(n) }
        let rest = n % 1000
        let head = "\(below1000(n / 1000)) thousand"
        if rest == 0 { return head }
        return head + (rest < 100 ? " and " : " ") + below1000(rest)
    }
}

/// Edit distance between two strings (insert/delete/substitute, each cost 1).
public enum Levenshtein {
    public static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    /// Allowed edits for a target of this length (FEATURES §3.4, ADR-0007):
    /// 0 for ≤3 characters (avoids "cat" == "bat"), 1 for 4–6, 2 for longer.
    public static func threshold(forLength length: Int) -> Int {
        switch length {
        case ...3: 0
        case 4...6: 1
        default: 2
        }
    }
}

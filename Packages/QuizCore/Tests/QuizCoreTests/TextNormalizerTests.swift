import Testing
@testable import QuizCore

@Suite("Text normalisation")
struct TextNormalizerTests {
    @Test(arguments: [
        ("The Pacific Ocean!", "pacific ocean"),
        ("  an Echidna  ", "echidna"),
        ("Don't", "dont"),
        ("Uluru (Ayers Rock)", "uluru ayers rock"),
        ("Café", "cafe"),
        ("1,000", "1000"),
        ("3.5", "3.5"),
        ("salt & pepper", "salt and pepper"),
    ])
    func normalises(input: String, expected: String) {
        #expect(TextNormalizer.normalize(input) == expected)
    }

    @Test func keepsArticlesInRawTokens() {
        #expect(TextNormalizer.tokens("Option A") == ["option", "a"])
    }
}

@Suite("Number words")
struct NumberWordsTests {
    @Test(arguments: [
        ("seven", "7"),
        ("twenty one", "21"),
        ("twenty-one", "21"),
        ("one hundred and five", "105"),
        ("a hundred", "100"),
        ("two thousand three hundred and forty five", "2345"),
        ("fifteen hundred", "1500"),
        ("one million", "1000000"),
        ("seven apples", "7 apples"),
        ("salt and pepper", "salt and pepper"),
        ("seven and eight", "7 and 8"),
        ("one two three", "1 2 3"),
        ("twenty thirty", "20 30"),
        ("21", "21"),
        ("zero", "0"),
    ])
    func converts(input: String, expected: String) {
        #expect(TextNormalizer.normalize(input) == expected)
    }

    @Test(arguments: [
        (0, "zero"), (1, "one"), (13, "thirteen"), (21, "twenty-one"), (40, "forty"),
        (105, "one hundred and five"), (1000, "one thousand"), (2045, "two thousand and forty-five"),
    ])
    func spells(n: Int, expected: String) {
        #expect(NumberWords.spell(n) == expected)
    }

    @Test func spellingRoundTrips() {
        for n in [0, 7, 19, 20, 99, 100, 101, 999, 1001, 12_345, 999_999] {
            #expect(TextNormalizer.normalize(NumberWords.spell(n)) == String(n), "round trip \(n)")
        }
    }
}

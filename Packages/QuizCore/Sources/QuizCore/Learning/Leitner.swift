import Foundation

/// Spaced repetition with Leitner boxes (ADR-0016).
///
/// Each player has their own boxes. A question starts in box 1 the day they first meet it.
/// Every time they get it right it moves up a box and comes back after a longer wait;
/// a wrong answer sends it back to box 1, for that player only. After box 6 it is learned
/// and isn't asked again. No question is played twice on the same day, so box 1 comes back
/// tomorrow at the earliest.
///
/// Reviews are a small, random share of each session (`ReviewMix`), so the game stays fresh.
public enum Leitner {
    /// Days to wait before a question in each box comes back:
    /// box 1 today, then tomorrow, 2, 4, 8 and 16 days.
    public static let intervals = [0, 1, 2, 4, 8, 16]
    public static var boxCount: Int { intervals.count }
}

/// How a scored question went for one player.
public enum ReviewResult: String, Codable, Sendable, Hashable {
    case correct
    case incorrect
    /// They heard the answer but nobody marked it (Listen mode in the car). Counts as
    /// correct, so hands-free play still spaces questions out; "Not yet" resets it (ADR-0016).
    case heard

    var movesUp: Bool { self != .incorrect }
}

/// One question's place in one player's boxes.
public struct ReviewCard: Codable, Hashable, Sendable {
    /// 1…6 while learning; `Leitner.boxCount + 1` once learned.
    public var box: Int
    /// `LearningDay` number on which it's next due.
    public var due: Int
    /// `LearningDay` number on which it was last played (asked, or heard as a bystander).
    public var last: Int

    public init(box: Int, due: Int, last: Int? = nil) {
        self.box = box
        self.due = due
        self.last = last ?? due
    }

    private enum CodingKeys: String, CodingKey { case box, due, last }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        box = try c.decode(Int.self, forKey: .box)
        due = try c.decode(Int.self, forKey: .due)
        last = try c.decodeIfPresent(Int.self, forKey: .last) ?? due
    }

    public var isLearned: Bool { box > Leitner.boxCount }
    public func isDue(on day: Int) -> Bool { !isLearned && due <= day }
}

/// Everything one player has learned. Stored on their profile, keyed by question id,
/// which is why question ids are permanent (CONTENT.md).
public struct LearningRecord: Codable, Hashable, Sendable {
    public private(set) var cards: [String: ReviewCard]
    /// Talk About prompts already discussed. They aren't spaced; fresh ones are preferred.
    public private(set) var talkedAbout: Set<String>

    public init(cards: [String: ReviewCard] = [:], talkedAbout: Set<String> = []) {
        self.cards = cards
        self.talkedAbout = talkedAbout
    }

    public func card(_ questionID: String) -> ReviewCard? { cards[questionID] }
    public func isNew(_ questionID: String) -> Bool { cards[questionID] == nil }
    public func isDue(_ questionID: String, on day: Int) -> Bool { cards[questionID]?.isDue(on: day) ?? false }
    public func isLearned(_ questionID: String) -> Bool { cards[questionID]?.isLearned ?? false }
    public func wasPlayed(_ questionID: String, on day: Int) -> Bool { cards[questionID]?.last == day }

    /// Moves the question up a box (correct or heard) or back to box 1 (incorrect).
    /// A question met for the first time counts as box 1 "today", so a right answer
    /// brings it back tomorrow.
    public mutating func record(_ result: ReviewResult, for questionID: String, on day: Int) {
        let box = result.movesUp ? (cards[questionID]?.box ?? 1) + 1 : 1
        let wait = box <= Leitner.boxCount ? Leitner.intervals[box - 1] : 0
        cards[questionID] = ReviewCard(box: min(box, Leitner.boxCount + 1), due: day + wait, last: day)
    }

    public mutating func noteTalkedAbout(_ questionID: String) { talkedAbout.insert(questionID) }

    /// Merges a newer record for the same player (the newer card wins).
    public mutating func merge(_ newer: LearningRecord) {
        cards.merge(newer.cards) { _, new in new }
        talkedAbout.formUnion(newer.talkedAbout)
    }

    // Decoded key by key so records written by older or newer builds still load.
    private enum CodingKeys: String, CodingKey { case cards, talkedAbout }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cards = (try? c.decodeIfPresent([String: ReviewCard].self, forKey: .cards)) ?? [:]
        talkedAbout = (try? c.decodeIfPresent(Set<String>.self, forKey: .talkedAbout)) ?? []
    }
}

/// Whole calendar days, so "tomorrow" means after midnight, not 24 hours later.
public enum LearningDay {
    public static func number(for date: Date = .now, calendar: Calendar = .current) -> Int {
        let origin = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))
        return calendar.dateComponents([.day], from: origin, to: calendar.startOfDay(for: date)).day ?? 0
    }
}

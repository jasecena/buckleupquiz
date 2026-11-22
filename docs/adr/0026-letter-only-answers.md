# 0026. Answers are the letter only

- **Status:** Accepted
- **Date:** 2026-11-22
- **Supersedes:** [ADR-0007](0007-answer-matching.md) rules 1, 3, 4, 5 and the option-text parts of rule 6
- **Amends:** [ADR-0018](0018-hands-free-voice-answers.md) (what counts as an answer)

## Context
Product decision (2026-11-22): "For educational questions, we need to exercise extra caution
and only say 'correct' when the student selects the right answer. Guide them to respond with A,
B, or C only. There is no need to check the full sentence. If a student gives the wrong answer
and we tell them it's correct, we are miseducating them."

The matcher accepted the option's words, fuzzy spellings (up to 2 edits), key-word overlap for
long options, and a match from *any* of the recogniser's guesses. Each of those is a way for a
wrong answer to be heard as right: a near-miss word within the edit distance, or one stray
guess among the recogniser's alternatives.

## Decision
- **Multiple choice:** only the option letter counts: "B", "option B", "I think it's B". The
  letter must be the only word apart from fillers (`AnswerMatcher.fillers`), so "A or B" and
  "B, Western Australia" are not answers. Recogniser spellings of a letter ("bee", "see") count.
- **True/false:** only "true" or "false" (with the same fillers: "it's true"). "Yes", "no",
  "right" and "wrong" no longer count.
- **The recogniser's guesses must agree.** Every alternative transcription that names an
  option must name the same one. If one hears "B" and another "D", the reply is unclear:
  listening carries on, and if it stays unclear the turn is quietly unheard (ADR-0018).
- The option's words, `acceptedAnswers`, fuzzy matching and key-word overlap are not used.
  `Levenshtein` is deleted.
- The kids are told once per game: "Say the letter, A, B or C, as soon as you know it!" The
  options are already read as "A: … B: … C: …". The recogniser is hinted with the letters only.
- Commands ("skip", "repeat", …) and "Joy, not correction" are unchanged: anything that isn't a
  clear letter is never counted against a child.

## Alternatives considered
- **Keep the option text, but exact only** — still a second path, and long scenario options are
  rarely transcribed word for word.
- **Use only the best guess** — simpler, but a disagreeing alternative is exactly the case where
  the recogniser isn't sure, so waiting is safer.

## Consequences
- A wrong answer can only be called right if the recogniser mishears one letter as another with
  all its guesses agreeing. Letters that sound alike ("B", "D", "E") are why every question has
  exactly 3 options (A, B, C).
- A child who says the answer's words isn't scored, and gets the plain answer reveal. The tip at
  the start teaches the letters.
- `acceptedAnswers` in the content is now unused by the app. It stays valid in the schema for
  now and can be removed in a later content clean-up.

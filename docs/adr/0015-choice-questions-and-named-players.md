# 0015. Every question is a choice; players are picked by name and age

- **Status:** Accepted
- **Date:** 2026-11-22
- **Amends:** FEATURES §2.1, §3.1, §4.1; [ADR-0007](0007-answer-matching.md) (the open-answer rules no longer apply)

## Context
Product decision (2026-11-22):

1. **All questions are single choice between several answers.** True/false is fine too.
   Free-answer ("open") questions are dropped.
2. **Families add their kids once, with name and age.** Each session starts with "Who's
   playing?", and the family picks names. There is no age-band picker: the app already knows
   each child's age, so each child gets questions for their own age. The names are used later
   too: turns, scores and voice mode.

## Decision
- `QuestionType` is now `multipleChoice | trueFalse | scenario | talkAbout`. The validator
  rejects `open` with a pointer to this ADR. Multiple choice needs 3–4 options; scenarios need
  2–4. Options are always read aloud, so the "read options" setting is gone.
  `acceptedAnswers` stays optional, as extra ways to say the *correct option*
  ("gum" for "Gum leaves").
- Talk About prompts stay. They are unscored chats rather than quiz questions, and are
  controlled by Parent mode.
- **Players** (`PlayerProfile`, SwiftData, CloudKit-ready per ADR-0009) have a name, an age
  (4–14), a colour, and the question ids they've heard. The age is stored with the date it was
  set, and the current age adds the years since, so kids move up a band on their own.
  Age → band: up to 8 → 6–8, 9–10 → 9–10, 11 and over → 11–12. Up to 6 players.
- **Session setup** is topic → "Who's playing?" (multi-select chips, add a player inline) →
  length → Start. Players take turns in list order ("Mia, this one's for you: …"). Each turn
  draws from that player's band, and prefers questions they haven't heard before (seen ids are
  saved when the session ends). Players whose band has no questions in the topic are flagged
  and skipped.
- Listen mode keeps no score, so the outro cheers the players by name.

## Consequences
- Voice matching gets easier and more reliable. The child says a letter or an option, so there
  are no free-text answers to fuzzy-match (ADR-0007's option rules still apply).
- Content work changes: every question needs 2–3 *plausible* wrong options.
- Players are now part of the free experience. Whether the free tier should limit the
  number of players is an open M6 (paywall) question.

# 0015. Every question is a choice; players are picked by name and age

- **Status:** Accepted
- **Date:** 2026-11-22
- **Amends:** FEATURES §2.1, §3.1, §4.1; [ADR-0007](0007-answer-matching.md) (the open-answer rules no longer apply)

## Context
Product decision (2026-11-22):

1. **All quiz questions are a single choice between three answers.** True/false is fine too.
   Free-answer quiz questions are dropped. "Scenario" was the same thing as multiple choice,
   and having both was confusing, so they are merged.
   **Talk About** prompts, the open discussion questions turned on by Parent mode, stay.
   They have **no time limit**, so nobody is rushed, and Parent mode is **off by default**.
2. **Families add their kids once, with name and age.** Each session starts with "Who's
   playing?", and the family picks names. There is no age-band picker: the app already knows
   each child's age, so each child gets questions for their own age. The names are used later
   too: turns, scores and voice mode.

## Decision
- `QuestionType` is now `multipleChoice | trueFalse | talkAbout`.
  - **multipleChoice** has **exactly 3 options**, one correct. Values and safety topics use it
    for everyday situations. Their gentle wording ("The best choice is…", "Good try! A kinder
    choice might be…") and `explanation` come from the topic's category, not from a separate
    type.
  - **trueFalse** has no options; the answer is "True" or "False".
  - **talkAbout** is an open discussion with no score. Parent mode has its **own section in
    Settings** with a **separate talk timer**: No limit (default), 30 s, 1, 2, 3 or 5 min. It is
    not tied to think time. The app says "Take your time and talk it over. Press next when
    you're ready." then waits (`SpeechStep.discuss(seconds:)`) until someone taps **We're done**
    / Next, presses the car's next-track button, or the timer runs out. Then it says "Great
    chat!". Parent mode is off by default.
    *(Amended 2026-11-22: an earlier draft gave it 2 × think time.)*
  
  The validator rejects `open` and `scenario` with a pointer to this ADR. Options are always
  read aloud, so the "read options" setting is gone.
  `acceptedAnswers` stays optional, as extra ways to say the *correct option*
  ("gum" for "Gum leaves").
- **Players** (`PlayerProfile`, SwiftData, CloudKit-ready per ADR-0009) have a name, an age
  (4–14), a colour, and their Leitner boxes ([ADR-0016](0016-leitner-spaced-repetition.md)). The age is stored with the date it was
  set, and the current age adds the years since, so kids move up a band on their own.
  Age → band: up to 8 → 6–8, 9–10 → 9–10, 11 and over → 11–12. Up to 6 players.
- **Session setup** is topic → "Who's playing?" (multi-select chips, add a player inline) →
  length → Start. Players take turns in list order ("Mia, this one's for you: …"). Each turn
  draws from that player's band: due reviews first, then new questions (ADR-0016; boxes are
  saved when the session ends). Players whose band has no questions in the topic are flagged
  and skipped.
- Listen mode keeps no score, so the outro cheers the players by name.

## Consequences
- Voice matching gets easier and more reliable. The child says a letter or an option, so there
  are no free-text answers to fuzzy-match (ADR-0007's option rules still apply).
- Content work changes: every multiple-choice question needs 2 *plausible* wrong options.
- Players are now part of the free experience. Whether the free tier should limit the
  number of players is an open M6 (paywall) question.

# 0007. Answer-matching rules

- **Status:** Accepted
- **Date:** 2026-11-22

## Context
Kids speak answers into a car microphone over Bluetooth HFP (8–16 kHz audio) with road noise.
The speech recognizer returns several alternative transcriptions. Targets: at least 90% correct
matching in a quiet room and at least 75% with road noise (FEATURES §9).

## Decision
`AnswerMatcher` in `QuizCore` implements these rules, all covered by unit tests:

1. **Normalise** both sides: fold case and accents, strip punctuation ("don't" → "dont"), drop
   "the/a/an", and convert number words to digits ("twenty one" → "21",
   "one hundred and five" → "105").
2. **Any alternative transcription** that matches counts.
3. **Open questions:** match the `answer` or any `acceptedAnswers` entry, either as the whole
   phrase or inside a short phrase ("I think it's Hobart"). The heard phrase may have at most
   4 extra words, so listing many guesses doesn't win.
4. **Fuzzy matching** uses Levenshtein distance scaled to length: **0 edits for 3 letters or
   fewer**, 1 edit for 4–6, and 2 for longer. This goes slightly beyond FEATURES §3.4's
   "≤1 for short words": "cat" must not accept "bat".
5. **Numbers are never fuzzy.** "21" never matches "22".
6. **Choice questions** accept, in order:
   - the option letter, including homophones ("B", "bee", "option B", "I think it's C")
   - for true/false, synonyms like "yes", "nope", "it's true"
   - the option text
   - for long scenario options, at least 50% of the option's key words, with a clear winner
   
   Naming two options ("Pacific or Atlantic") is treated as a hedge and is wrong.
7. **Voice commands** ("skip", "repeat", "pause", "stop", "next") only count as exact short
   phrases, so a real answer is never taken as a command.
8. Silence returns `.noAnswer`. The app then says "Time's up". Retrying after a garbled answer
   is the app's job (M4).

## Consequences
- The rules are deterministic and live in one place. M4's 100-answer field test set
  (FEATURES §9) will tune the thresholds by adding test cases, not by guessing.
- Option shuffling happens before matching (`PresentedQuestion`), so letters always match what
  was read out.

# 0029. Voice answers only while the app is on screen; the screen stays on

- **Status:** Accepted
- **Date:** 2026-11-22
- **Amends:** [ADR-0028](0028-mic-on-for-the-whole-game.md) (the mic is off in the background)

## Context
After ADR-0028 the microphone kept running with the screen locked (the orange dot showed),
but nothing was heard. Back on screen, answers were heard again (tested on a phone,
2026-11-22). Apple's speech recognition doesn't work for an app in the background. Apple
doesn't document this, and other developers report the same thing (errors such as
kAFAssistantErrorDomain 1700, or no results at all). An app can't keep itself in front of
other apps, but it can stop the screen from locking by itself.

## Decision
- **Screen on:** during a voice game the screen doesn't auto-lock (`isIdleTimerDisabled`).
  It locks normally again when the game ends. Listen-mode games don't need this.
- **In the background** (the screen locked by hand, or another app opened) the mic is turned
  off, so the orange dot doesn't show while nothing can hear. The game carries on as in
  Listen mode: think time with the tick, then "The answer is…". An unheard answer counts as
  remembered, as before (ADR-0016), and nothing is said about it.
- **Back on screen** the mic comes on again, and the next question is answered out loud.
- The rest of ADR-0028 stands: on screen the mic runs for the whole game, a phone call gives
  it back afterwards, and a long pause turns it off.
- **No winner after the background:** if a voice game went to the background at any point,
  the scores and the winner aren't announced or shown at the end, because answers there weren't
  heard. The same goes for a game where more than 2 answers weren't heard (silence, mumbles, a
  failed mic). The game ends with "Great job, Mia and Leo!" and nothing is said about why
  ("joy, not correction"). Points still count towards badges and stats. Listen mode is scored
  by taps, so it always shows its scores.
- Settings → Answers and the "Keep playing in the background?" question say that answers are
  only heard while the app is on screen.

## Alternatives considered
- **Keep the mic on in the background anyway** — it shows the orange dot and uses battery
  for nothing.
- **Pause the game in the background** — "Keep playing in the background" is still useful:
  the questions and answers carry on through the car speakers.
- **Send audio to a server for recognition** — against ADR-0004 (nothing leaves the device).

## Consequences
- The phone should sit in a cradle with the app open during a voice game. A phone that's
  charging in the car is the normal case. Without a charger the screen uses more battery.
- Onboarding should say so (PROGRESS, "Onboarding").
- If a later iOS lets speech recognition run in the background, this can be revisited:
  try SpeechAnalyzer (iOS 26) in the background on a real phone first.

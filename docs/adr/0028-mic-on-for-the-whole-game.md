# 0028. The microphone stays on for the whole game

- **Status:** Accepted
- **Date:** 2026-11-22
- **Amends:** [ADR-0018](0018-hands-free-voice-answers.md) (how the mic is opened for each answer)

## Context
With the screen locked or another app open, voice answers stopped working: the app read the
question and then never heard the answer. Each answer used to start a new audio engine and
turn the microphone on, then turn it off afterwards. iOS lets an app with background audio
**keep** the microphone running in the background, but not **start** it there. So the first
answer after the phone was locked failed to start the mic, and the game then switched voice
off for the rest of that game.

## Decision
- One microphone stream (`MicInput`) is started when the game starts, while the app is on
  screen, and runs until the game ends. Both recognisers (SFSpeechRecognizer and iOS 26's
  SpeechAnalyzer) listen on it.
- Between answers its audio goes nowhere. It's only passed to the recogniser while it listens,
  and it's never recorded, stored or sent anywhere (ADR-0004).
- A route change (the car connects, headphones come out) stops the engine, so it's started
  again straight away. Before each answer it's started again if a call or interruption stopped it.
- If the mic is busy for one answer (a phone call), the game reads the answer out as usual
  and tries the mic again next turn, instead of turning voice off for the whole game.
  Anything else (Dictation off) still turns voice off for that game.
- **After a phone call** the app takes the audio session back and starts the mic again before
  the game carries on, instead of waiting for the next answer.
- **A paused game** keeps the mic on for up to 5 minutes, so the car's play button still
  resumes hands-free with the screen locked. After that the mic is turned off, and play turns
  it back on (or, if iOS won't allow it with the screen locked, the next answer tries again).
- When the game ends, by finishing, the ✕ button or leaving the screen, the mic is turned off
  and the audio is handed back to iOS.
- Mic check still turns the mic on only for its own test.

## Alternatives considered
- **Start the mic per answer, from the foreground only** — answers wouldn't work with the
  screen locked, which is the normal way to use the app in a car.
- **Keep listening the whole time** — the app would hear its own voice and the car's music as
  answers, and the recogniser would run for no reason.

## Consequences
- The orange microphone dot shows for the whole game in voice mode, not only while
  listening. That's honest (the mic really is on) and fits "Answers are understood on this
  iPhone and never recorded."
- Cars that show a phone-call screen while the mic is on (ADR-0008) may show it for the
  whole game. The audio session was already in play-and-record for the whole game, so the
  route doesn't change.
- Must be checked on a real phone: lock the screen mid-game, answer by voice, and also a
  phone call mid-game in the background (see PROGRESS, "Phone-call interruption").

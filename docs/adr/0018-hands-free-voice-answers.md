# 0018. Hands-free voice answers with turn-based scoring

- **Status:** Accepted
- **Date:** 2026-11-22
- **Amends:** [ADR-0008](0008-audio-architecture.md) (voice session mode); FEATURES §3.2–3.5; [ADR-0016](0016-leitner-spaced-repetition.md) (voice grades the boxes)

## Context
Product decision (2026-11-22): now that players take turns, the app should **listen** for
answers and keep score. There is no speaker identification: whoever's turn it is gets the
result. It must be **completely hands-free**, with nothing to tap, because it's played in a
moving car. If phone or car microphones turn out not to be good enough, a later option is
selling kids' microphones that plug into the phone. So the mic choice must handle external
mics.

## Decision
- **Answers setting:** "Say them out loud" (voice, the default) or "Just listen" (the old
  Listen mode, no score). Microphone: "Car or headset if connected" (default) or "This iPhone".
- **Recognition:** `SFSpeechRecognizer` with **`requiresOnDeviceRecognition`** (en-AU, else
  en-US). Audio never leaves the phone and nothing is recorded (ADR-0004). If on-device
  recognition isn't available, voice is unavailable and the app reads the answers out.
- **Permission** is asked the first time a voice game starts. If it's refused, Answers switches
  to "Just listen", and Settings → Mic check can ask again.
- **Audio session:** `.playAndRecord`, mode `.default`,
  `[.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker, (.duckOthers)]`. The preferred
  input is the first of Bluetooth HFP, CarPlay, wired headset mic or USB mic, else the built-in
  mic. A plugged-in kids' mic works with no code change. The screen shows "Using: <mic>".
  `.voiceChat` (from ADR-0008) was dropped: it made speech quieter on the phone speaker, and
  half-duplex already avoids echo.
- **Per turn (half-duplex):** question and options → 300 ms → chime → listen. Listening ends
  1.2 s after speech stops, or after the think time with no speech (plus up to 4 s to finish
  an answer already started). The reply is judged by `VoiceReply` in QuizCore:
  - **command** ("skip"/"next", "repeat", "pause", "stop") → obeyed;
  - **answer** → `AnswerMatcher` (letters, option text, true/false words, every alternative
    transcription) → "Correct! Awesome!" plus a streak cheer from 3 in a row, or "Not quite,
    the answer was B: Hobart.";
  - **mumble** ("umm", "hmm") → "Sorry, I didn't catch that. Say it again?" once, then time's up;
  - **silence** → "Time's up! The answer was…".
- **Scoring** uses the existing `ScoreKeeper`: +10, plus a +5 streak bonus from the third right
  answer in a row. A live scoreboard sits at the top of the screen. At the end, the app reads
  the scores aloud ("Mia wins with 80 points!") and announces new badges. Lifetime points,
  streaks and per-topic stats are saved per player (`PlayerProfile.statsData`). Badges come
  from `BadgeRules` and show in Players.
- **Leitner boxes** (ADR-0016) use the spoken result: right → up a box, wrong or time's up →
  start over. The "Got it / Not yet" buttons only appear in "Just listen" mode.
- **Talk About** is hands-free too: while the family chats, the app listens for "we're done",
  "all done", "finished" or "next", alongside the Parent mode timer.
- **Safety net:** after **three silent turns in a row**, the app says "I can't hear any
  answers, so I'll read them out instead." and continues in Listen mode. If the recogniser
  fails (route change, mic taken), it falls back straight away.

## Alternatives considered
- **Speaker identification** to credit whoever answered — no on-device API for it. It's also
  unreliable for kids' voices, and turns make it unnecessary.
- **Server recognition** (Apple or cloud) — sends children's audio off the device, which is
  against ADR-0004 and the Kids Category rules.
- **Always listening (no chime)** — the mic would pick up the question being read. A chime
  also tells kids when to talk.

## Consequences
- Accuracy depends on the car: HFP microphones are narrowband and road noise hurts. The M4
  field test set (quiet and road noise) will tune `AnswerMatcher` and the silence timing.
  External kids' mics are the fallback plan.
- Some head units show a call screen while HFP is active (ADR-0008 already notes this).
- A silent child loses the point and the box (time's up counts as wrong), but the safety net
  stops a broken mic from wiping a whole session's progress after three turns.
- Voice answers are meant for the Family Pass (FEATURES §3). They stay open until the
  paywall lands in M6.

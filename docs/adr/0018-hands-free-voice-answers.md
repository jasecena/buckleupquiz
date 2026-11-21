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
- **Naming the player:** "Mia, this one's for you!" on each player's first turn of a game,
  then just "Mia.", a short pause (0.6 s) and the question.
- **Per turn (half-duplex):** question and options → 500 ms → chime → 500 ms → listen. The gaps
  keep the mic from catching the question's tail or the chime through laggy Bluetooth
  speakers. Listening only ends early on a **conclusive** reply (an answer that picks an
  option, or a command) followed by a 1.2 s pause. Chatter, echo and mumbles keep it
  listening for the whole think time (plus up to 4 s to finish an answer already started).
- **Recogniser resilience** (v0.3.1, after the first device test answered at once): the app
  tries every on-device English recogniser (the phone's language, en-AU, en-US, en-GB, …).
  One that stops within 2 s with nothing heard (for example its model isn't installed) is
  skipped and moved to the back. If none work, or the mic won't start, that turn finishes its
  think time as a Listen-mode countdown and the game continues in Listen mode. The reason is
  shown in Settings → Mic check.
- The reply is judged by `VoiceReply` in QuizCore:
  - **command** ("skip"/"next", "repeat", "pause", "stop") → obeyed. Skipping before the
    answer keeps the turn with the same player: "Here's another one.", same question number,
    and the skipped question doesn't use up the game's length (product decision, 2026-11-22).
    After the answer, Next moves on to the next player;
  - **answer** → `AnswerMatcher` (letters, option text, true/false words, every alternative
    transcription) → "Correct! Awesome!" plus a streak cheer from 3 in a row. A wrong answer
    must name another option; random words never count as wrong. A wrong answer
    gets no comment: the app just shares it ("The answer is… B: Hobart!"), as Listen mode does;
  - **mumble or silence** → nothing is said about it. The answer is shared and the game moves
    on (see "Joy, not correction" below).
- **Scoring** uses the existing `ScoreKeeper`: +10, plus a +5 streak bonus from the third right
  answer in a row. A live scoreboard sits at the top of the screen. At the end, the app reads
  the scores aloud ("Mia wins with 80 points!") and announces new badges. Lifetime points,
  streaks and per-topic stats are saved per player (`PlayerProfile.statsData`). Badges come
  from `BadgeRules` and show in Players.
- **Leitner boxes** (ADR-0016) use the spoken result: right → up a box, wrong → start over,
  not heard → untouched. The "Got it / Not yet" buttons only appear in "Just listen" mode.
- **Talk About** is hands-free too: while the family chats, the app listens for "we're done",
  "all done", "finished" or "next", alongside the Parent mode timer.
- **Joy, not correction** (product decision, 2026-11-22): "It's all about knowledge and joy.
  If we don't hear it, it's okay. We silently don't hear it."
  - If we heard an answer, we record it. If not, we move on: no "Sorry, I didn't catch that",
    no "Time's up", no retry. An unheard turn (`AnswerOutcome.unheard`) scores nothing, keeps
    the streak and leaves the Leitner boxes alone.
  - Nothing says or shows failure: no "Not quite", no ✗ on screen. Only right answers get a
    line ("Correct!"). Everything else is the plain answer reveal.
  - Nobody is announced with zero points: they get "Great listening, Leo!", and if nobody
    scored, the ride ends with "Great job, Mia and Leo!".
  - Listening carries on every turn, even after several silent ones, since an unheard turn
    takes no longer than a Listen-mode turn and kids may join in later. If the recogniser
    fails (route change, mic taken), the app quietly continues in Listen mode.

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
- A broken or poor mic can't hurt anyone's progress: unheard turns change nothing.
- A child who stays quiet on purpose doesn't lose their streak. That's accepted: joy over
  strictness.
- Voice answers are meant for the Family Pass (FEATURES §3). They stay open until the
  paywall lands in M6.

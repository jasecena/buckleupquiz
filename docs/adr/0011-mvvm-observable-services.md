# 0011. MVVM with `@Observable` models and protocol-based services

- **Status:** Accepted
- **Date:** 2026-11-22

## Context
FEATURES §1 asks for MVVM, a separate `QuizEngine` and an `AudioService`. The audio and timing
logic is the riskiest part, and it must be testable without real audio or real time passing.

## Decision
- **Views** are thin SwiftUI views. **View models** are `@MainActor @Observable` classes, for
  example `ListenSessionModel`.
- **Game rules** live in `QuizCore`, which is pure and synchronous: `QuizSession`,
  `AnswerMatcher`, `ListenScript`. View models orchestrate; they don't decide.
- **Platform services** sit behind `@MainActor` protocols: `SpeechOutput`, `CuePlaying`,
  `AudioSessionControlling`, `NowPlayingUpdating`, and the `Sleeper` for time. Real
  implementations wrap AVFoundation and MediaPlayer. Tests use fakes and an instant sleeper,
  so a whole session runs in milliseconds.
- **`AppEnvironment`** is the composition root. It builds the live services and is injected
  through the SwiftUI environment. There are no singletons in feature code.
- **Concurrency:** Swift 6 strict checking. Long-running work (a session) is one cancellable
  `Task`. Pausing cancels it, and a generation counter stops a cancelled task from touching
  newer state.

## Consequences
- Listen-mode behaviour (pause/resume, interruptions, remote commands) is unit-tested in
  `App/Tests` on the simulator.
- A little boilerplate per service (protocol + live + fake), which pays for itself in
  testability.

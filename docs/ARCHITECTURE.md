# Architecture

BuckleUp Quiz is an offline, native iOS app. The game rules live in a pure-Swift package. The
app layer handles audio, UI and persistence. See the [ADRs](adr/README.md) for the reasoning.

```mermaid
flowchart TB
  subgraph App["App target (iOS, SwiftUI)"]
    Views["Views<br/>Home · Setup · Quiz · Settings"]
    VM["ListenSessionModel<br/>(@Observable, @MainActor)"]
    Env["AppEnvironment<br/>(composition root)"]
    subgraph Services["Services (protocols + live impls)"]
      Speech["SpeechOutput<br/>AVSpeechSynthesizer"]
      Cues["CuePlaying<br/>AVAudioEngine"]
      Session["AudioSessionControlling<br/>AVAudioSession"]
      NowPlaying["NowPlayingUpdating<br/>MediaPlayer"]
      Settings["SettingsStore<br/>UserDefaults"]
      Ent["EntitlementStore<br/>(StoreKit 2 in M6)"]
    end
  end
  subgraph Core["QuizCore (pure Swift, Linux-testable)"]
    QS["QuizSession<br/>turns · selection · scoring"]
    Script["ListenScript + Phrases"]
    Match["AnswerMatcher<br/>letters · TextNormalizer"]
    Source["QuestionSource → QuestionBank"]
  end
  Content[("Content/<br/>topics.json<br/>questions/*.json")]

  Views --> VM
  Views --> Env
  Env --> Services
  VM --> Speech & Cues & Session & NowPlaying
  VM --> QS & Script
  QS --> Match
  Env --> Source
  Source --> Content
```

## Listen-mode loop

For each turn, `QuizSession.advance()` picks the next question for the next player.
`ListenScript.steps(for:)` turns it into steps:

```
say(number) → say(question) → say(options)? → cue(think) → think(8s) → say(answer) → say(fun fact)? → wait(2s)
```

`ListenSessionModel` runs these steps in a single cancellable `Task`:

- **Pause** cancels the task. **Resume** re-runs the current step: it re-reads a sentence, or
  continues the countdown from where it stopped.
- **Skip** jumps to the next turn. **Repeat** jumps back to the question step.
- **Interruptions** (phone calls) pause. When they end, the app says "Welcome back!" and
  repeats the question.
- **Remote commands** map to play, pause, skip and repeat.

## Voice mode (M4, planned)

Same loop, with `cue(listening)` + `listen(thinkTime)` in place of the plain think step.
Transcripts go to `VoiceCommand.parse`, then to `AnswerMatcher.match`, then
`QuizSession.record`, then `Phrases.feedback` is spoken. The audio session is `.playAndRecord`
over Bluetooth HFP, fixed for the whole session (ADR-0008).

## Where things go

| You're adding… | Put it in |
|---|---|
| A rule about answers, scoring, selection or wording | `Packages/QuizCore` + a test |
| Anything touching AVFoundation, StoreKit, SwiftData, UIKit | `App/Sources/Services/…` behind a protocol |
| A screen | `App/Sources/Features/<Feature>/` |
| Questions or topics | `Content/` (see [CONTENT.md](CONTENT.md)) |
| A structural decision | `docs/adr/` |

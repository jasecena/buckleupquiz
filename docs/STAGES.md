# Delivery stages

Status key: ✅ done · 🟡 in progress · ⬜ not started

The stages follow FEATURES §8 (M1–M8), with an M0 foundation stage and a later backend stage
(M9). Each stage ends with its exit criteria met and CI green.

| Stage | Goal | Status |
|---|---|---|
| M0 | Foundation: repo, ADRs, CI, Pages | ✅ |
| M1 | Engine (`QuizCore`) | ✅ |
| M2 | Listen mode audio | 🟡 |
| M3 | UI | 🟡 |
| M4 | Voice answers + car Bluetooth mic | ⬜ |
| M5 | Players & scoring | ⬜ (engine side ✅) |
| M6 | Paywall & parental gate | ⬜ |
| M7 | Content & polish | ⬜ |
| M8 | TestFlight & real-car testing | 🟡 (pipeline ✅) |
| M9 | Backend (cloud data, content packs) | ⬜ (ADR-0012 proposed) |

---

## M0 — Foundation ✅
- [x] Monorepo layout, XcodeGen spec, `.gitignore`, `.editorconfig`, Makefile (ADR-0003)
- [x] ADRs 0001–0013
- [x] CI: content validation and `QuizCore` tests on Linux, app build and tests on macOS (ADR-0013)
- [x] GitHub Pages deploy for privacy and support pages (ADR-0005)
- [x] Privacy manifest (`PrivacyInfo.xcprivacy`), permission strings
- [x] Placeholder app icon (`scripts/make_icon.py`), replaced by the mascot in M3
- [x] TestFlight pipeline `ios-release.yml` + `certificates.yml` (ADR-0014, [RELEASING.md](RELEASING.md))

**Exit:** a push to `main` runs CI green.

## M1 — Engine ✅
- [x] Models: `Question` (FEATURES §4.1 schema), `Topic` catalogue, `AgeBand`, `Player`
- [x] `QuestionSource` + `DirectoryQuestionSource` (bundled JSON), `QuestionBank` index
- [x] `AnswerMatcher`: normalisation, number words, Levenshtein, choice letters,
      true/false synonyms, scenario key-word overlap, hedge detection (ADR-0007)
- [x] `VoiceCommand` parsing
- [x] `QuestionSelector`: no repeats within a session, prefer unseen, `minAge`, Talk About toggle
- [x] `PresentedQuestion`: shuffled options, correct letter
- [x] `ScoreKeeper` (+10, +5 streak bonus from the 3rd), `Scoreboard` with ties, `BadgeRules`
- [x] `QuizSession`: turn rotation with each player's own age band, session length, seen tracking
- [x] `ListenScript` + `Phrases`: everything the app says, gentle wording for values topics
- [x] 47 unit tests, including "every bundled answer is accepted"

**Exit:** `make test-core-docker` green ✅

## M2 — Listen mode 🟡
- [x] `SystemSpeechOutput` (AVSpeechSynthesizer, en-AU default, rate, cancellable)
- [x] `AudioSessionController`: `.playback`/`.spokenAudio`, ducking option, interruptions, output lost
- [x] `EngineCuePlayer`: think tick, listening chime, quiet keep-alive (ADR-0008)
- [x] `NowPlayingController`: lock screen info, play/pause/next/previous remote commands
- [x] `ListenSessionModel`: script runner, pause/resume mid-countdown, skip, repeat,
      "Welcome back" after interruptions, unit tests with fakes
- [ ] Verify on device: a 20-question session with the screen locked, over Bluetooth, with no taps
- [ ] Phone-call interruption test on device
- [ ] Tune TTS rate and voice for HFP/car speakers

**Exit:** acceptance criteria 1–2 (FEATURES §9) pass on a real device.

## M3 — UI 🟡
- [x] Home topic grid (icon, name, count, lock), topic setup (age band, length), quiz screen
      (question, countdown ring, answer reveal, big Pause/Skip/Repeat), settings
- [ ] Onboarding (FEATURES §6): welcome, 3-question demo, optional first player
- [ ] Mascot and app icon (original, not seatbelt-themed)
- [ ] Mixed-topic sessions (paid)
- [ ] Accessibility pass: Dynamic Type, VoiceOver labels, contrast
- [ ] iPad layout pass

**Exit:** a parent can install, choose a topic and play without instructions.

## M4 — Voice answers & car mic ⬜
- [ ] `SpeechRecognizer` service: `SFSpeechRecognizer`, `requiresOnDeviceRecognition`, all alternatives
- [ ] Voice audio session: `.playAndRecord` + `.voiceChat`, HFP input selection, "Using: <car>" label
- [ ] Voice processing (echo cancellation); half-duplex speak → 300 ms → chime → listen
- [ ] Silence detection (about 1.2 s after speech), retry once on garbled input, voice commands
- [ ] Route-change fallback (phone mic/speaker or pause, per the "Microphone source" setting)
- [ ] Mic check screen; HFP onboarding note
- [ ] 100-answer field test set (quiet + road noise) feeding `AnswerMatcher` tests

**Exit:** acceptance criteria 3–7 pass.

## M5 — Players & scoring ⬜
- [ ] SwiftData models (CloudKit-compatible, ADR-0009), repositories
- [ ] Player profiles (up to 6: name, age band, avatar/colour), pick players per session
- [ ] Turn-based voice sessions using `QuizSession` rotation (engine ✅)
- [ ] Spoken and on-screen scoreboard, per-player stats, badges (engine ✅)
- [ ] Persist seen questions per player

**Exit:** acceptance criterion 8 passes.

## M6 — Paywall & parental gate ⬜
- [ ] StoreKit 2 Family Pass (lifetime), `.storekit` config, restore, Family Sharing (ADR-0010)
- [ ] `EntitlementStore` backed by `Transaction.currentEntitlements`
- [ ] Parental gate before purchases, settings, links and support email
- [ ] Locked topics, Endless mode and custom mixes enforced

**Exit:** acceptance criterion 9 passes in the StoreKit sandbox.

## M7 — Content & polish ⬜
- [ ] About 1,500 questions: 8 knowledge topics × 3 bands × 60 or more
- [ ] Manners & Friendship: at least 40 scored + 20 Talk About per band; other values and safety topics
- [ ] Parent/teacher review of values and safety content; First Nations content with
      Aboriginal and Torres Strait Islander input
- [ ] `make validate-strict` green
- [ ] Sounds, app icon, App Store screenshots, privacy policy final text and custom domain

**Exit:** strict validation green and reviews signed off.

## M8 — TestFlight 🟡
- [x] Signing + tag-triggered TestFlight workflow (ADR-0014)
- [ ] One-time App Store Connect app record + API key secrets ([RELEASING.md](RELEASING.md))
- [ ] First internal TestFlight build (v0.1.0)
- [ ] Real-car tests: 3 or more head units plus CarPlay, road noise, kids
- [ ] Proxy test: zero network requests (criterion 10)
- [ ] Name checks (IP Australia), domains and handles (FEATURES §0)

**Exit:** all FEATURES §9 acceptance criteria pass, ready for App Review.

## M9 — Backend (later) ⬜
- [ ] Accept ADR-0012 (CloudKit sync + remote content packs; AWS only if needed)
- [ ] Remote `QuestionSource` with signed, versioned content packs
- [ ] SwiftData CloudKit sync toggle
- [ ] Privacy label, policy and parental consent updates

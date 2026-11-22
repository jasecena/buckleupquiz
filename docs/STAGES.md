# Delivery stages

For a plain-language summary of done and remaining work, see [PROGRESS.md](PROGRESS.md).

Status key: ✅ done · 🟡 in progress · ⬜ not started

The stages follow FEATURES §8 (M1–M8), with an M0 foundation stage and a later backend stage
(M9). Each stage ends with its exit criteria met and CI green.

| Stage | Goal | Status |
|---|---|---|
| M0 | Foundation: repo, ADRs, CI, Pages | ✅ |
| M1 | Engine (`QuizCore`) | ✅ |
| M2 | Listen mode audio | 🟡 |
| M3 | UI | 🟡 |
| M4 | Voice answers + car Bluetooth mic | 🟡 (built; needs real-car testing) |
| M5 | Players & scoring | 🟡 (players, live and spoken scoreboard, lifetime stats ✅) |
| M6 | Paywall & parental gate | ⬜ |
| M7 | Content & polish | ⬜ |
| M8 | TestFlight & real-car testing | 🟡 (first build on TestFlight ✅) |
| M9 | Backend (cloud data, content packs) | ⬜ (ADR-0012 proposed) |
| M10 | Natural voice packs (ElevenLabs) | ⬜ (ADR-0019; plans and costs agreed) |
| M11 | Progress for parents (Leitner view) | ⬜ |
| M12 | Sponsor messages for more free questions | ⬜ (ADR-0024) |

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
- [x] `AnswerMatcher`: option letters and true/false only, recogniser guesses must agree
      (ADR-0007, ADR-0026)
- [x] `VoiceCommand` parsing
- [x] `QuestionSelector`: once per player per session, Leitner due-first then new, `minAge`, Talk About toggle
- [x] `PresentedQuestion`: shuffled options, correct letter
- [x] `ScoreKeeper` (+10, +5 streak bonus from the 3rd), `Scoreboard` with ties, `BadgeRules`
- [x] `QuizSession`: turn rotation with each player's own age band, session length, Leitner records
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
- [x] Quiz questions are 3-option multiple choice or true/false; Talk About (Parent mode, off by default) with its own timer, default 30 s, No limit optional (ADR-0015)
- [x] Players: add/edit with name, age and colour (rename only, never deleted: ADR-0025); "Who's playing?" replaces the age picker;
      turns per player with age-appropriate questions (ADR-0015)
- [x] Leitner boxes per player (today, 1, 2, 4, 8, 16 days; wrong → start over), "Got it" / "Not yet"
      after each answer, permanent question ids with `retired-ids.json` (ADR-0016)
- [x] Review mix: ~80% new, 10% own reviews, 10% shared from the others; nothing twice a day;
      bystanders move up on right answers only (ADR-0016)
- [x] One-tap start: remembered players and length, Play = random topic, tap a topic = start,
      Game setup only first time or via Change (ADR-0017)
- [ ] Onboarding (FEATURES §6): welcome, 3-question demo, add the first player
- [ ] Mascot and app icon (original, not seatbelt-themed)
- [ ] Mixed-topic sessions (paid)
- [ ] Accessibility pass: Dynamic Type, VoiceOver labels, contrast
- [ ] iPad layout pass

**Exit:** a parent can install, choose a topic and play without instructions.

## M4 — Voice answers & car mic 🟡
- [x] `SystemSpeechListener`: `SFSpeechRecognizer`, `requiresOnDeviceRecognition`, all alternatives (ADR-0018)
- [x] Voice audio session: `.playAndRecord`, HFP/CarPlay/headset/USB input preferred, "Using: <mic>" label
- [x] Half-duplex speak → 300 ms → chime → listen (`.default` mode instead of `.voiceChat`, ADR-0018)
- [x] Silence detection (1.2 s after speech), voice commands, hands-free Talk About
- [x] Skip/Next before the answer keeps the turn with the same player ("Here's another one.")
- [x] "Mia, this one's for you!" on a player's first turn only, then "Mia." and a pause
- [x] Listening waits the full think time unless an option or command is heard; recogniser
      fallback across on-device English locales; Mic check shows why listening failed
- [x] Joy, not correction: unheard turns aren't mentioned or scored; no "Not quite", no ✗, no zero-point announcements
- [x] Fallbacks: recogniser error → quietly read answers out; permission refused → "Just listen"
- [x] Mic check screen (Settings → Answers) with the HFP call-screen note
- [ ] Verify on device and in 3+ cars; tune silence timing and the speech rate for HFP
- [ ] 100-answer field test set (quiet + road noise) feeding `AnswerMatcher` tests

**Exit:** acceptance criteria 3–7 pass.

## M5 — Players & scoring ⬜
- [x] SwiftData `PlayerProfile` (CloudKit-compatible, ADR-0009) + `PlayerStore`
- [x] Player profiles (up to 6: name, age, colour), pick players per session (done early, in M3)
- [x] Turn-based voice sessions using `QuizSession` rotation; whoever's turn it is gets the score (ADR-0018)
- [x] Scoreboard visible from the first question for named players; in Listen mode "Got it" scores
- [x] Equal questions per player (length rounded to a multiple of players; repeats or nearest-age questions when someone runs out)
- [x] Fix scores after the game (pencil, − / + by 10, capped), announced after the scores
- [x] Fix guides for known mic/speech errors (Mic check + in-game note)
- [x] Settings: Show the scoreboard (default on); Keep playing in the background (asked once, the first time)
- [x] Listening view shows the microphone and the countdown side by side; "Not listening" note when voice is off
- [x] Live on-screen scoreboard, spoken end-of-game scores, streak cheers, new-badge announcements
- [x] Lifetime per-player stats (`PlayerProfile.statsData`), points and badges in Players
- [ ] Per-player stats screen (accuracy per topic, badge gallery)
- [x] Persist each player's Leitner boxes
- [x] Players can only be renamed, never deleted; tombstones removed from the backup (ADR-0025)

**Exit:** acceptance criterion 8 passes.

## M6 — Paywall & parental gate 🟡 ([ADR-0022](adr/0022-free-allowance-packs-and-basic-subscription.md))
- [x] Free allowance (30 per free topic + 2 a day opened; Manners 10), question packs (50 for A$0.99),
      BuckleUp Basic (A$4.99/month: all topics, 40 new each day the app is opened, 6 players, fix scores)
- [x] Games planned up front; 0–2 each blocks, 3–4 warns, 5 each minimum; lengths are questions each
- [x] StoreKit 2 store (products, purchase, restore, Transaction.updates), plans screen, parental gate
- [x] Paid Applications agreement, banking and tax (account holder); launch prices A$0.99 pack, A$4.99/month Basic
- [ ] Create the products in App Store Connect
- [x] Progress survives a reinstall: iCloud key-value storage + Keychain backup, merged at launch (ADR-0023)
- [x] No Endless mode; games are 5/10/15 each, at most 50 questions
- [ ] Parental gate before settings, links and support email
- [ ] Locked topics and custom mixes enforced
- [x] Free games: up to 2 players; BuckleUp Basic: up to 6 (Game setup note + alert). TestFlight-only switch to try Basic until purchases land

**Exit:** acceptance criterion 9 passes in the StoreKit sandbox.

## M7 — Content & polish ⬜
- [x] +150 questions (2026-11-22): Animals, Geography, Maths, Space, Manners now 40–45 each (211 total)
- [ ] About 1,500 questions: 8 knowledge topics × 3 bands × 60 or more
- [ ] Content for Aussie History, Science, Sport, Food and a second values topic, so BuckleUp Basic's "10 topics" are all playable
- [ ] Manners & Friendship: at least 40 scored + 20 Talk About per band; other values and safety topics
- [ ] Parent/teacher review of values and safety content; First Nations content with
      Aboriginal and Torres Strait Islander input
- [ ] `make validate-strict` green
- [ ] Sounds, app icon, App Store screenshots, privacy policy final text and custom domain

**Exit:** strict validation green and reviews signed off.

## M8 — TestFlight 🟡
- [x] Signing + tag-triggered TestFlight workflow (ADR-0014)
- [x] One-time App Store Connect app record + API key secrets ([RELEASING.md](RELEASING.md))
- [x] First TestFlight upload: 0.1.0 (2), 2026-11-22
- [x] Internal testing group "Family" (gets every build automatically) with the account holder invited
- [x] Tester "Reset all data" in Settings → Testing, TestFlight and debug only (ADR-0027)
- [ ] Build with the iOS 27 SDK (Xcode 27) before April 2027 (App Store Connect warning 90725). The release workflow picks the newest non-beta Xcode on the runner; set `vars.MACOS_RUNNER_LABEL` if a newer image is needed
- [ ] Real-car tests: 3 or more head units plus CarPlay, road noise, kids
- [x] Anonymous error reports (ADR-0020): `Telemetry` queue + batches, MetricKit crashes/hangs,
      voice failure events, per-game voice counts, Settings toggle + Diagnostics screen
- [x] Terraform for AWS: bootstrap (state bucket), domain (buckleupquiz.com, zone, certificate), platform (CloudFront, content bucket, reports Lambda) (ADR-0021)
- [x] Applied bootstrap (state bucket, least-privilege deployer role + boundary) and platform; `TELEMETRY_URL` set (CloudFront address)
- [x] buckleupquiz.com registered (Route 53), certificate issued, platform on api.buckleupquiz.com, site on buckleupquiz.com
- [x] Domain contact verified; buckleupquiz.com verified in App Store Connect
- [ ] Update the App Store privacy label (Diagnostics, not linked) before the public release
- [ ] Proxy test: only the telemetry endpoint, only anonymous fields (criterion 10, amended by ADR-0020)
- [ ] Name checks (IP Australia), domains and handles (FEATURES §0)

**Exit:** all FEATURES §9 acceptance criteria pass, ready for App Review.

## M11 — Progress for parents (later) ⬜
- [ ] A screen per child showing their Leitner boxes: questions learned for good (past the 16-day
      box), on the way, and coming back for review, per topic, over time
- [ ] "What Mia knows now": the learned questions with their answers, to celebrate progress

## M12 — Sponsor messages (later) ⬜ ([ADR-0024](adr/0024-sponsor-audio-for-more-questions.md))
- [ ] Find family-friendly sponsors; legal check (AANA children's code, COPPA/CARU) and an App Review pre-check
- [ ] Sponsor audio on the CDN (`/sponsors/`), reviewed by us; anonymous play counts only
- [ ] Parent opt-in behind the parental gate; messages between games, clearly announced
- [ ] Rewards: daily top-up 5 instead of 2 with messages on; +2 questions per extra message, daily cap
- [ ] Never in BuckleUp Basic

## M9 — Backend (later) ⬜
- [ ] Accept ADR-0012 (CloudKit sync + remote content packs; AWS only if needed)
- [ ] Remote `QuestionSource` with signed, versioned content packs
- [ ] SwiftData CloudKit sync toggle
- [ ] Privacy label, policy and parental consent updates
- [ ] Accounts (random account id; players' name and age; question history per player) and the
      admin app (questions, voices, users, promote to unlimited), ADR-0025. Not before the privacy check

## M10 — Natural voice packs ⬜ ([ADR-0019](adr/0019-natural-voice-packs.md), proposed)
- [ ] Decide the open questions in ADR-0019 (own database or CloudKit, voices, names, free or paid)
- [ ] Voice bake-off: 20 questions × 3 providers, kids and parents choose; licence check
- [ ] `Phrases` → speech plans (fixed segments with clip ids); segment player with on-device fallback
- [ ] Generation pipeline (`scripts/voices/`, content-hash keyed, CI on content changes)
- [ ] S3 + CloudFront via CDK in `infra/`; signed per-voice manifests
- [ ] `VoicePackStore`: Free = 1 voice, 10-question batches deleted after the game; Basic = 3 voices,
      up to 500 questions cached, learned questions' audio deleted (ADR-0019 amendment)
- [ ] Selector prefers questions with cached audio; Settings → Voice with samples and download status
- [ ] Amend ADR-0004, privacy policy and App Review notes for the content download

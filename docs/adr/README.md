# Architecture Decision Records

Each significant decision gets a short, numbered record. ADRs are immutable once
accepted: to change a decision, add a new ADR that supersedes the old one.

| # | Decision | Status |
|---|---|---|
| [0001](0001-record-architecture-decisions.md) | Record architecture decisions | Accepted |
| [0002](0002-native-ios-swiftui.md) | Native iOS 17+ with SwiftUI and Swift 6 | Accepted |
| [0003](0003-repository-layout.md) | Monorepo, XcodeGen and a pure-Swift `QuizCore` package | Accepted |
| [0004](0004-privacy-no-network-no-sdks.md) | No network, no third-party SDKs, no data collection | Accepted |
| [0005](0005-static-hosting-github-pages.md) | Host static pages on GitHub Pages, not AWS | Accepted |
| [0006](0006-bundled-json-content.md) | Bundled JSON content with a topic catalogue and CI validation | Accepted |
| [0007](0007-answer-matching.md) | Answer-matching rules | Accepted (open-answer parts amended by 0015) |
| [0008](0008-audio-architecture.md) | Audio: one session mode per session, half-duplex, cue engine | Accepted |
| [0009](0009-persistence.md) | SwiftData for players and stats, UserDefaults for settings | Accepted |
| [0010](0010-storekit2-purchases.md) | StoreKit 2 with on-device verification, lifetime pass first | Accepted |
| [0011](0011-mvvm-observable-services.md) | MVVM with `@Observable` models and protocol-based services | Accepted |
| [0012](0012-future-backend.md) | Future backend: Apple-native services first, AWS serverless as fallback | Proposed |
| [0013](0013-ci-cd-github-actions.md) | CI/CD on GitHub Actions: Linux for logic, macOS for the app | Accepted |
| [0014](0014-testflight-release-pipeline.md) | TestFlight releases: tag-triggered, cloud-managed signing | Accepted |
| [0015](0015-choice-questions-and-named-players.md) | Every question is a choice; players picked by name and age | Accepted |
| [0016](0016-leitner-spaced-repetition.md) | Each player learns with Leitner boxes (spaced repetition) | Accepted |
| [0017](0017-one-tap-start.md) | One tap to play: remembered setup, random or chosen topic | Accepted |
| [0018](0018-hands-free-voice-answers.md) | Hands-free voice answers with turn-based scoring | Accepted |
| [0019](0019-natural-voice-packs.md) | Natural voices: pre-generated audio, downloaded 10 questions at a time | Proposed |
| [0020](0020-anonymous-error-telemetry.md) | Anonymous error reports (first-party telemetry) | Accepted |

New ADR: copy [template.md](template.md) to the next number.

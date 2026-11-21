# BuckleUp Quiz

[![CI](https://github.com/jasecena/buckleupquiz/actions/workflows/ci.yml/badge.svg)](https://github.com/jasecena/buckleupquiz/actions/workflows/ci.yml)

A hands-free, voice-first educational quiz for kids aged 6–12, made for car trips. The app reads
a question aloud, waits, then reveals the answer. The paid tier listens for spoken answers,
takes turns between players and keeps score.

> "Turn 'are we there yet?' into 'ask me another!'"

- **Platform:** iOS 17+ (iPhone first, iPad compatible), SwiftUI, Swift 6
- **Privacy:** no network, no accounts, no analytics. Audio never leaves the device.
- **Status:** early development. See [docs/STAGES.md](docs/STAGES.md).

## Repository layout

```
App/                 iOS app — SwiftUI features, view models, audio/platform services, tests
Packages/QuizCore/   Pure-Swift game engine (matching, scoring, selection, scripts) + tests
Content/             Question bank: topics.json + questions/<topic>.json
scripts/             Content validator (+ tests), CI helpers
docs/                FEATURES, STAGES, ARCHITECTURE, CONTENT guide, ADRs
site/                Privacy policy & support pages (GitHub Pages)
backend/ infra/      Reserved for a future backend (ADR-0012)
project.yml          XcodeGen spec (the .xcodeproj is generated)
```

## Getting started

**macOS (full app):**

```sh
brew install xcodegen
make open          # generates BuckleUpQuiz.xcodeproj and opens Xcode
make test-app      # build + test on the newest iPhone simulator
```

**Any OS (engine + content):**

```sh
make test-content      # validator unit tests (Python 3, stdlib only)
make validate          # check the question bank
make test-core-docker  # QuizCore tests in the swift:6.1 Docker image
```

**Release to TestFlight:** `git tag v0.1.0 && git push origin v0.1.0`. See [docs/RELEASING.md](docs/RELEASING.md).

Run `make help` for every target.

## Documentation
- [Feature spec](docs/FEATURES.md)
- [Delivery stages](docs/STAGES.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Architecture decision records](docs/adr/README.md)
- [Writing questions](docs/CONTENT.md)
- [Releasing to TestFlight](docs/RELEASING.md)

## Licence
No licence has been chosen yet, so all rights are reserved. Please don't reuse the code or
content without permission.

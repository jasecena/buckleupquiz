# 0003. Monorepo, XcodeGen and a pure-Swift `QuizCore` package

- **Status:** Accepted
- **Date:** 2026-11-22

## Context
- `.xcodeproj` files are machine-written, merge badly, and can't be generated or reviewed on
  Linux.
- FEATURES §1 asks for a `QuizEngine` that is pure Swift and unit-testable.
- A backend may come later (ADR-0012), and content will grow to about 1,500 questions.

## Decision
One repository:

```
App/              iOS app target (SwiftUI views, view models, platform services)
Packages/QuizCore Swift package: models, loading, matching, scoring, selection, scripts
Content/          topics.json + questions/*.json (the bundled question bank)
scripts/          content validator (+ tests) and CI helpers
docs/             FEATURES, STAGES, ARCHITECTURE, CONTENT guide, ADRs
site/             static privacy/support pages (GitHub Pages)
backend/, infra/  reserved for the future backend (ADR-0012)
project.yml       XcodeGen spec — the .xcodeproj is generated, never committed
```

- **XcodeGen** generates the Xcode project from `project.yml` (`make generate`).
- **`QuizCore`** imports only Foundation: no UIKit, AVFoundation or SwiftUI. It builds and tests
  on Linux (in Docker or the CI container) as well as on macOS. It holds everything that can be
  tested without a device: answer matching, number words, scoring, selection, session state
  and the spoken script.
- The app target depends on `QuizCore` as a local package.

## Alternatives considered
- **Committed `.xcodeproj`** — merge conflicts, and it can't be reviewed.
- **Tuist** — more powerful, but heavier, and it changes often. XcodeGen is enough for one app
  and one test target.
- **One target with no package** — logic tests would need a simulator, so they would be slow
  and macOS-only.

## Consequences
- Contributors on macOS must `brew install xcodegen` and run `make generate`.
- Fast logic tests (about 1 second) on any machine; CI runs them on cheap Linux runners.
- `QuizCore` must stay platform-free. Code review checks for stray `import AVFoundation`.

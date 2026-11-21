# 0013. CI/CD on GitHub Actions: Linux for logic, macOS for the app

- **Status:** Accepted
- **Date:** 2026-11-22

## Context
The repository is public on GitHub. iOS builds need macOS. Most of the logic (`QuizCore`,
content) doesn't.

## Decision
`.github/workflows/ci.yml` runs on every push to `main` and on every PR:

| Job | Runner | What |
|---|---|---|
| `content` | ubuntu-latest | validator unit tests + validate `Content/` |
| `core` | ubuntu-latest, `swift:6.1` container | `swift test` for `QuizCore` |
| `app` | `macos-26` (Xcode 26.x) | XcodeGen → `xcodebuild test` on the newest iPhone simulator, unsigned |

- Standard GitHub-hosted runners, including macOS, are **free for public repositories**.
- The simulator is chosen at runtime (`scripts/ci/simulator-destination.sh`), so Xcode device
  renames don't break CI.
- The `.xcresult` bundle is uploaded when tests fail.
- `pages.yml` deploys `site/` (ADR-0005). Dependabot keeps action versions current.
- **TestFlight:** see [ADR-0014](0014-testflight-release-pipeline.md), a tag-triggered
  `ios-release.yml` with cloud-managed signing. Credentials are encrypted repository secrets
  and are never committed (`.gitignore` blocks `*.p8`, `*.p12`).

## Alternatives considered
- **Xcode Cloud** — 25 free compute hours a month, with simple signing. But it adds a second CI
  system, and its free tier is smaller than unlimited public-repo minutes. Worth revisiting
  for signing convenience in M8.
- **Bitrise / Codemagic** — paid beyond small free tiers, for no real benefit here.

## Consequences
- Fast feedback: logic and content failures show up in about a minute on Linux.
- If the repository goes private, macOS minutes become billable (10× multiplier), and
  Xcode Cloud becomes the cheaper choice.

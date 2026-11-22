# 0004. No network, no third-party SDKs, no data collection

- **Status:** Accepted, amended by [ADR-0020](0020-anonymous-error-telemetry.md) (anonymous error reports to our own endpoint)
- **Date:** 2026-11-22

## Context
The app targets Apple's **Kids Category** (ages 6–12). Apple forbids third-party analytics and
advertising there and requires a parental gate for links and purchases. Australian privacy law
and COPPA also apply to children's data. Parents need to trust that a microphone app is safe.

## Decision
- **No runtime network requests** in v1. All content is bundled.
- **No third-party runtime dependencies** at all: no analytics, crash SDKs, ads or tracking.
  Dev tools (XcodeGen, xcbeautify) are fine because they never ship in the app.
- Audio is never recorded or stored. Speech recognition uses `requiresOnDeviceRecognition`.
- App Privacy label: **Data Not Collected**. `PrivacyInfo.xcprivacy` declares no tracking and
  only the required-reason APIs we use (UserDefaults: CA92.1).
- A parental gate guards purchases, settings, external links and support email (M6). Since
  2026-11-22 it asks to type three numbers written as words ("seven, two, nine"); a sum like
  17 × 8 was too hard for a parent in the car. iOS has no built-in gate for this.
- Crash insight comes from Xcode Organizer and TestFlight, which are Apple's opt-in
  diagnostics and need no SDK.

## Consequences
- Simpler compliance and App Review, and a strong message for parents.
- No product analytics: decisions come from TestFlight feedback and App Store Connect data.
- Any future backend (ADR-0012) must keep this promise, or update the privacy label and add
  parental consent *before* shipping. A proxy test in M8 checks for zero network traffic.

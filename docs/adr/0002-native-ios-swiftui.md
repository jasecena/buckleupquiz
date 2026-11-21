# 0002. Native iOS 17+ with SwiftUI and Swift 6

- **Status:** Accepted
- **Date:** 2026-11-22

## Context
The product depends on deep, low-level iOS audio behaviour: Bluetooth HFP and A2DP routing,
voice-processing echo cancellation, on-device `SFSpeechRecognizer`, background audio,
`MPRemoteCommandCenter`, CarPlay later, and StoreKit 2. FEATURES §1 sets iOS 17+, SwiftUI and
no Android for v1.

## Decision
- Native iOS app in **Swift 6** (strict concurrency checking) with **SwiftUI**.
- Minimum deployment target **iOS 17.0**. This gives `@Observable`, SwiftData and StoreKit 2
  views, and still covers almost every device in use.
- Built with the current Xcode (26.x). Apple requires the latest SDK for App Store submission.
- iPhone first, with iPad supported (universal target).

## Alternatives considered
- **Flutter / React Native** — would give us Android, which is out of scope, but the audio
  session, HFP routing and on-device speech work would all need native plugins anyway, and these
  are the riskiest parts of the app.
- **Kotlin Multiplatform for shared logic** — `QuizCore` is pure Swift and could be ported later
  if Android happens. Too early to pay that cost.

## Consequences
- The best possible access to the audio stack, with no bridge layer to debug in a moving car.
- Android would be a separate project. Keeping the game logic in a pure package (ADR-0003)
  and the content as JSON (ADR-0006) keeps a port affordable.

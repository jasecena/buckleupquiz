# 0020. Anonymous error reports (first-party telemetry)

- **Status:** Accepted. The endpoint is defined in Terraform by [ADR-0021](0021-aws-infrastructure-terraform.md).
- **Date:** 2026-11-22
- **Amends:** [ADR-0004](0004-privacy-no-network-no-sdks.md) (first network request; the privacy label changes)

## Context
In the first device test (v0.3.0), the microphone didn't work and we had no way to know why.
Apple's own diagnostics (Xcode Organizer, TestFlight crash reports) only cover crashes and
hangs, and only from people who opted into sharing with developers. They never show handled
errors like "the microphone didn't start" or "this speech recogniser isn't installed".

Product decision (2026-11-22): "We don't collect people's data, but we need … errors that we
are facing, so we can improve the application."

## Decision
**First-party, anonymous error reports**, sent to our own endpoint. There's no third-party SDK
(Kids Category guideline 1.3 / 5.1.4).

### What's collected
| Event | When | Fields |
|---|---|---|
| `voice.micStartFailed` | the audio session can't record | error, domain, code |
| `voice.listenFailed` | the mic or every recogniser failed mid-game | error, domain, code, input type |
| `voice.recognizerFailed` | one on-device recogniser stopped at once | locale, error |
| `voice.noPermission`, `voice.noOnDeviceRecognizer` | voice answers can't start | reason |
| `audio.activateFailed`, `content.loadFailed` | setup failures | error |
| `game.finished` | end of each game | mode, turns, players count, right/wrong/unclear/silent/failed counts, input type, fell back |
| `metrickit.crash` / `hang` / `cpuException` / `diskWriteException` / `launch` | Apple MetricKit delivers a diagnostic | MetricKit's JSON (call stacks, device info) |

Every batch also carries: app version, build, iOS version, hardware model (e.g. `iPhone15,3`),
and a **random ID per app launch** (so one launch's events read together; it's never stored
and changes every launch). Times are rounded down to the hour.

### What's never collected
Names, ages, answers, transcripts or audio, the mic's device name (e.g. "Jason's AirPods":
we send only the port *type*), any device or advertising identifier, location or IP
address (the endpoint never logs it). Field values are capped at 500 characters.

### On the device
- `Telemetry` queues up to 300 events in Application Support and sends them in batches of 20
  on launch and when the app goes to the background. Failures are silent; it retries next
  time. It uses an ephemeral `URLSession` with no cookies or cache.
- **Settings → Privacy → "Send anonymous error reports"**, on by default. Turning it off
  deletes the queue and stops recording. **Settings → Privacy → Diagnostics** shows exactly
  what's queued, and a tester can share it by hand.
- The endpoint comes from the `TELEMETRY_URL` build setting (Info.plist `BUQTelemetryURL`).
  While it's empty, reports stay on the device and in Diagnostics.

### The endpoint (AWS, per the hosting preference)
- `https://api.buckleupquiz.com/v1/reports`: CloudFront in front of a Lambda **function URL**
  (Node 22, arm64, 128 MB) in **ap-southeast-2**. It validates each batch and logs each event
  as structured JSON to the `/buckleupquiz/telemetry` log group, kept **90 days**. No database,
  and no IP or headers are logged. Defined in Terraform (`infra/terraform/platform`,
  [ADR-0021](0021-aws-infrastructure-terraform.md)). The first draft was a CloudFormation
  template.
- Cost: within the Lambda free tier, plus CloudWatch Logs ingestion (cents per month at this
  scale). Reserved concurrency can cap abuse (`MaxConcurrency`).
- Reading reports: CloudWatch Logs Insights (queries in [RELEASING.md](../RELEASING.md)).

### Store and policy changes
- `PrivacyInfo.xcprivacy` declares Crash Data, Performance Data and Other Diagnostic Data,
  **not linked** to the user, **not used for tracking**, purpose App Functionality.
- The App Store privacy label changes from "Data Not Collected" to **"Data Not Linked to You:
  Diagnostics"**. This must be updated in App Store Connect before the first public release
  (TestFlight doesn't need it).
- The privacy policy (`site/privacy.html`) describes the reports.

## Alternatives considered
- **Apple only (Organizer, TestFlight, MetricKit kept on device)**: misses handled errors and
  non-opted-in users. MetricKit is used, but forwarded to our endpoint.
- **Sentry, Firebase Crashlytics, TelemetryDeck**: third-party SDKs in a Kids Category app,
  against ADR-0004 and riskier in App Review.
- **Off by default (opt-in)**: few parents would turn it on, and we'd stay blind to problems like
  the one that prompted this. The reports hold nothing personal, are disclosed in Settings, the
  policy and the label, and are one switch away from off.

## Consequences
- We can see, per iPhone model and iOS version, why voice answers fail, and how often answers
  are heard in real cars (`game.finished` counts).
- The app makes its first network request; the "zero network requests" proxy test (M8)
  becomes "only the telemetry endpoint, only anonymous fields".
- New events must follow the table's rules: counts, error descriptions and enums only, never
  anything a child said or typed.

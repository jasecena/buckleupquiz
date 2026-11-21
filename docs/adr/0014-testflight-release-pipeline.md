# 0014. TestFlight releases: tag-triggered, cloud-managed signing (same as activity-tracker)

- **Status:** Accepted
- **Date:** 2026-11-22
- **Refines:** [ADR-0013](0013-ci-cd-github-actions.md) (TestFlight is brought forward from M8)

## Context
We want builds on TestFlight early, to test on real phones and in real cars. There is no Mac
in the loop. The owner's activity-tracker app already ships to TestFlight from GitHub Actions
on the same Apple team, and its pipeline is proven, so this app should work the same way.

## Decision
Use the activity-tracker pipeline, adapted for a native XcodeGen project:

- **`.github/workflows/ios-release.yml`** runs on a `vX.Y.Z` tag push, or manually (a
  rehearsal, optionally without uploading).
  - **Linux gates first:** content validation and `QuizCore` tests.
  - **macOS job** in the `ios-release` environment:
    1. XcodeGen
    2. Remove any pinned development identity
    3. App Store Connect preflight
    4. Archive
    5. Validate the archive
    6. Export the IPA (`app-store-connect`)
    7. `altool --validate-app`
    8. `altool --upload-app`
- **Cloud-managed signing.** An App Store Connect API key plus `-allowProvisioningUpdates`
  lets Xcode create or fetch the certificates and profiles. They go into an ephemeral keychain
  that is deleted at the end. No `.p12` and no profiles live in the repository.
- **Certificate hygiene.** Certificates are snapshotted before the run, and the ones the run
  created are revoked after it (`scripts/asc-certificates.mjs`, shared with activity-tracker).
  This stops the account hitting Apple's certificate limit. `certificates.yml` lists or revokes
  certificates by hand.
- **Preflight** (`scripts/asc-preflight.mjs`) registers the App ID if it's missing. It fails
  within seconds if the App Store Connect app record doesn't exist, because the API can't
  create one.
- **Versioning:** the tag sets `MARKETING_VERSION`, and `github.run_number` sets
  `CURRENT_PROJECT_VERSION`. Both are build settings, so the tree is never rewritten.
- **Configuration**, following the activity-tracker conventions:
  - Variables: `IOS_BUNDLE_IDENTIFIER=com.jcena.buckleupquiz`, `APPLE_TEAM_ID`, and an
    optional `MACOS_RUNNER_LABEL`.
  - Secrets: `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`,
    `APP_STORE_CONNECT_PRIVATE_KEY` (the same App Manager key as activity-tracker).
  
  The team id is never committed.
- **Public repo safety:** the IPA is never uploaded as a workflow artifact, only logs and dSYMs.
  Secrets aren't available to fork PRs. All inputs and secrets reach scripts through `env`.

## Consequences
- Shipping is `git tag v0.1.0 && git push origin v0.1.0`.
- One-time manual setup in App Store Connect: create the app record (see
  [RELEASING.md](../RELEASING.md)).
- Automatic signing archives with a development identity, so the team needs at least one
  registered device. This is already true for this Apple team.
- Improvements to either app's pipeline should be ported to the other.

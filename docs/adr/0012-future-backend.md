# 0012. Future backend: Apple-native services first, AWS serverless as fallback

- **Status:** Proposed. Content packs decided by [ADR-0031](0031-downloaded-question-updates.md): signed static files on our CDN, for every iOS version (built for 0.4.0). Cloud data is still proposed.
- **Date:** 2026-11-22

## Context
v1 ships with no backend (ADR-0004). A backend is expected later for two reasons:

1. **A lighter app.** Ship a small core and download content packs on demand (more topics,
   seasonal packs, maybe pre-recorded audio).
2. **Cloud data.** Keep players, stats and progress across devices and reinstalls.

Constraints: Kids Category rules (no tracking, parental gate), Australian privacy law and
COPPA, and minimal cost. The default host is AWS, unless a cheaper option made for apps exists.

## Options

| Need | Apple-native (preferred) | Other cheap option | AWS |
|---|---|---|---|
| Content packs | **Apple-hosted Background Assets** (iOS 26+; storage included in the developer membership) or the **CloudKit public database** (free tier grows with users) | Cloudflare R2 (no egress fees) | S3 + CloudFront (1 TB/month egress free tier) |
| Player data sync | **SwiftData + CloudKit private database**: lives in the family's own iCloud, so no accounts to build and no data collected by us | — | Cognito + API Gateway + Lambda + DynamoDB |
| Server logic (e.g. purchase webhooks) | App Store Server Notifications → a function | Cloudflare Workers | Lambda |

## Proposed decision
- **Cloud data → CloudKit private database via SwiftData sync.** Cost is $0. There are no
  accounts or passwords for kids, and the data stays in the parent's iCloud, so the privacy
  label can stay close to "Data Not Collected". ADR-0009 already models data to be
  CloudKit-ready.
- **Content packs → the `QuestionSource` protocol with a remote implementation.** It can use
  Apple-hosted Background Assets (iOS 26+), falling back to the CloudKit public database or a
  static CDN for iOS 17–25. Packs are signed and versioned JSON, checked by the same validator,
  and the bundled bank stays as the offline baseline.
- **AWS only if needed:** for cross-platform (Android), server-side logic, or a parent
  dashboard. Then use serverless (S3 + CloudFront, API Gateway + Lambda, DynamoDB), defined
  as code with AWS CDK (TypeScript) in `infra/`, with service code in `backend/`.

## Consequences
- `backend/` and `infra/` are reserved in the monorepo now, so adding them later doesn't
  reshuffle the repo.
- Any network feature needs a new ADR, an updated privacy label and policy, a parental gate
  if it involves accounts, and an update to the "no network" acceptance test.
- To be accepted when the backend work is scheduled (stage M9 in STAGES.md).

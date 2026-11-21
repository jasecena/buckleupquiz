# 0010. StoreKit 2 with on-device verification, lifetime pass first

- **Status:** Accepted
- **Date:** 2026-11-22

## Context
FEATURES §3.7: the **Family Pass** is a lifetime A$9.99 non-consumable. A subscription is
optional and later. Restore Purchases and Family Sharing are required. There is no backend
(ADR-0004).

## Decision
- **StoreKit 2** with `Transaction.currentEntitlements` and `Transaction.updates`.
  Verification uses the `VerificationResult` signed with Apple's JWS, on the device. There is no
  receipt server.
- Product id: `com.jasecena.buckleupquiz.familypass`, with Family Sharing enabled.
- `EntitlementStore` is the single source of truth for what is unlocked. The v1 scaffold uses a
  stored flag, and M6 swaps in StoreKit without touching the UI.
- A **`.storekit` configuration file** lets the simulator and CI test purchases, restore and
  refunds without App Store Connect.
- The paywall and Restore button are both behind the **parental gate** (ADR-0004).
- The subscription products can be added later. The entitlement check becomes "lifetime OR
  active subscription".

## Consequences
- No server and no cost. A jailbroken device could fake an entitlement, which is acceptable
  for a A$9.99 kids app.
- If a backend arrives, App Store Server Notifications can be added without changing the
  client's entitlement logic.

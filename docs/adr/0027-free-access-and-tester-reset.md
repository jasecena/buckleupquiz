# 0027. Giving free access the standard way, and a tester reset

- **Status:** Accepted
- **Date:** 2026-11-22
- **Amends:** [ADR-0025](0025-accounts-admin-and-rename-only-players.md) ("Promote to unlimited"),
  [ADR-0022](0022-free-allowance-packs-and-basic-subscription.md) (TestFlight switch)

## Context
The product owner wants to give some people full access without paying (family, testers,
friends), following standard practice and **avoiding anything alarming**: no extra personal
data, no device identifiers, no new permissions, nothing App Review could see as a way around
in-app purchase, and nothing a parent would be surprised by.

Testers also need to start over (for example to see the first-game flow and the free
allowance again) without deleting the app, which doesn't work anyway: the backup in the
Keychain and iCloud brings everything back (ADR-0023).

## Decision
### Free access, in three steps
| When | Who | How |
|---|---|---|
| **Now** | Family and testers | **TestFlight.** TestFlight builds have the "BuckleUp Basic (testing)" switch in Settings. Nothing to set up and nothing collected. |
| **After launch** | Someone on the App Store version | **Apple offer codes** for BuckleUp Basic, made in App Store Connect and redeemed in the App Store. Access follows their Apple ID (and their family, with Family Sharing on). Codes run for a set time and can be issued again. |
| **With accounts (M9)** | Chosen families, with no end date | **An admin-only `unlimited` flag** on the account (ADR-0025). Nothing in the app unlocks it; the app only reads its entitlement. |

### Never
- **Our own unlock codes, secret words or hidden gestures** in the app. App Review guideline
  3.1.1 doesn't allow apps to unlock features with their own mechanisms (license keys, QR codes,
  promo codes), and hidden features risk rejection. Offer codes are Apple's way to do this.
- **Access tied to a device** (device or vendor identifier). It's against ADR-0004/0020 and the
  Kids Category, and the vendor identifier resets when the app is deleted anyway.
- Asking for an email, phone number or Apple ID to give access.

### Tester reset (TestFlight only)
Settings → Testing → **Reset all data**, with a confirmation. It deletes the players and their
progress and scores, the questions used, packs credited, settings and the Basic test switch,
on this iPhone and in its iCloud and Keychain backup, so the app starts as if just installed.
- It only exists in TestFlight and debug builds (`EntitlementStore.isTestBuild`). The App Store
  version keeps "rename only" (ADR-0025); this is the one place players are deleted.
- Purchases aren't touched: StoreKit keeps them with the Apple ID.
- Another iPhone on the same iCloud account still has its own copy and can bring it back.

## Alternatives considered
- **A tester password or code in the App Store build** — 3.1.1, and it would be found and shared.
- **Deleting the app to reset** — doesn't reset: the Keychain and iCloud backup restore everything.

## Consequences
- Nothing to build for free access before accounts exist. After launch it's a few clicks in
  App Store Connect.
- `unlimited` is the only free access we build ourselves, and it waits for accounts and their
  privacy check (ADR-0025).

# 0023. Progress survives a reinstall: iCloud key-value storage + Keychain

- **Status:** Accepted
- **Date:** 2026-11-22
- **Relates to:** [ADR-0022](0022-free-allowance-packs-and-basic-subscription.md) (allowance), [ADR-0009](0009-swiftdata-persistence.md) (players), [ADR-0012](0012-future-backend.md) (backend), [ADR-0004](0004-privacy-no-network-no-sdks.md) (privacy)

## Context
Product direction (2026-11-22):
- A family that deletes the app and installs it again (or gets a new iPhone) gets their
  progress back by default: players, review boxes, scores, which questions they've had.
- Reinstalling must not reset the free allowance ("start over with the same questions").
- No personal ID: only something Apple allows, like a device identifier.

## Decision
**No account and no identifier of ours.** The app keeps one backup, saved in two places that
iOS provides, and merges every copy it finds at launch:

1. **iCloud key-value storage** (`NSUbiquitousKeyValueStore`, entitlement
   `com.apple.developer.ubiquity-kvstore-identifier`). This lives in the family's own iCloud,
   follows their Apple ID to a reinstall or a new iPhone, and needs no CloudKit container. Up to
   1 MB. Changes from another device arrive through `didChangeExternallyNotification`.
2. **The Keychain** (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, not synchronised). iOS
   keeps Keychain items when an app is deleted, so a reinstall on the same iPhone restores
   everything even with iCloud off.

The backup (`ProgressSync.Backup`) holds:
- the allowance state: questions heard, daily top-ups, Basic's daily use, credited pack
  transactions, pack questions used;
- players (id, name, age, colour, Leitner record, stats);
- deleted players, kept so a backup can't bring them back. *(Amended by ADR-0025: players can't be deleted any more; the list is always empty.)*

It's written a second after any change. **Merging never loses anything and never gives free
questions twice:** questions heard are a union, packs are a union of transaction ids, usage
counters take the maximum, and each review card keeps the most recent answer
(`LearningRecord.mergeKeepingLatest`).

The subscription needs none of this. StoreKit restores it from the Apple ID
(`Transaction.currentEntitlements`, plus Restore purchases).

## Alternatives considered
- **identifierForVendor**: resets when the app is deleted (if it's the vendor's only app), so it
  can't stop a reinstall resetting the allowance. And on its own it's just an id: the data
  still has to live somewhere.
- **Our own server keyed by a device id**: we'd hold children's progress, which brings
  COPPA/APP consent, a changed privacy label and deletion duties (ADR-0012). iCloud gives the
  same result while the data stays the family's.
- **CloudKit (SwiftData sync)**: the right tool once records outgrow 1 MB. It needs an iCloud
  container in the developer portal. Planned, not needed yet.
- **DeviceCheck** (2 bits per device, kept by Apple through reinstalls and even erasing): a
  stronger anti-abuse signal if it's ever needed. It needs our server and a DeviceCheck key.
  Kept in reserve.

## Consequences
- Privacy label unchanged ("Data Not Collected" by us apart from diagnostics, ADR-0020):
  iCloud and the Keychain are the user's own storage. The privacy policy says the app keeps
  progress in the family's iCloud and on the device.
- A family with iCloud off who erases or changes their iPhone starts fresh. That's acceptable.
- Key-value storage is capped at 1 MB. Past that, the backup still goes to the Keychain, and
  moving players to CloudKit becomes the next step.
- Release signing now includes the iCloud key-value entitlement (automatic signing adds the
  capability to the App ID).

# 0025. Accounts, the admin app, and players that can only be renamed

- **Status:** Accepted for rename-only players (built in 0.3.6). Proposed for accounts and the
  admin app (later, with M9). Amended by [ADR-0027](0027-free-access-and-tester-reset.md): free
  access uses TestFlight now and App Store offer codes after launch, until accounts exist; and
  TestFlight builds have a "Reset all data" button, the one place players are deleted.
- **Date:** 2026-11-22
- **Relates to:** [ADR-0012](0012-future-backend.md) (backend), [ADR-0016](0016-leitner-spaced-repetition.md) (boxes),
  [ADR-0022](0022-free-allowance-packs-and-basic-subscription.md) (allowance), [ADR-0023](0023-progress-survives-reinstall.md) (backup),
  [ADR-0004](0004-privacy-no-network-no-sdks.md) and [ADR-0020](0020-anonymous-error-telemetry.md) (privacy)

## Context
Product direction (2026-11-22):
- An admin UI is needed later to manage **questions, voices and users**.
- We collect no personal details. A user (family account) is only an **account id**, plus each
  player's **name and age**.
- For each player in an account, we keep a record of **which questions they've had**.
- **Players are never deleted, only renamed.**
- Some accounts can be **promoted to unlimited** (everything BuckleUp Basic gives, without a
  subscription) from the admin app. This is not built yet.

## Decision

### 1. Players can only be renamed (now)
- The app has no "Remove player". The editor changes a player's name, age and colour. To give a
  spot to someone else, a parent renames the player and changes the age.
- The player's id never changes. Their question history (Leitner record: question id → box, due
  day, last day played, plus Talk About prompts) stays with them through every rename.
- This removes the deletion markers ("tombstones") from the store and the backup. Nothing needs
  reconciling across devices, and deleting players and adding them again can't be used to get
  more free questions. The backup still writes an empty `deletedPlayers` field, so builds before
  0.3.6 can read it.
- Up to 6 players per family (unchanged). Free games still take 2 of them at a time.

### 2. Question history per player (now, on the device)
This is already kept, and the backup carries it:
- **Account (family):** `AllowanceStore.State.unlocked`: every question anyone in the family has
  heard, so it's never charged twice. It also holds top-ups, Basic's daily use and packs.
- **Player:** `PlayerProfile.learning`: every question this player has had and where it is in
  their boxes.

When accounts arrive (below), the server stores the same two levels.

### 3. Accounts (later, with M9)
- **Account id:** a random id created by the app (a UUID). It is not linked to an Apple ID,
  email, phone or device id. It is saved in the existing iCloud and Keychain backup, so it
  survives reinstalls (ADR-0023).
- **Stored per account:** the account id, the players (player id, name, age, colour), each
  player's question history, the family's allowance, and the entitlement: `free`, `basic`
  (verified with the App Store) or `unlimited` (set by an admin).
- **Never stored:** email, phone, parent name, location, recordings, device identifiers or
  advertising ids.
- **Family code:** Settings shows a short code derived from the account id. A parent can read it
  to us, which is how an admin finds the account to promote it. This makes the code an
  identifier, so it is shown only behind the parental gate.

### 4. The admin app (later)
A private web app for the owner only. On AWS, following ADR-0021: a static site on CloudFront,
API on Lambda, data in DynamoDB, sign-in for admins only (no public sign-up).
- **Questions:** list, search, add, edit, retire (never delete: ids are permanent, ADR-0016),
  review values and safety wording, publish a content version.
- **Voices:** per question and voice, the generation status. Listen, regenerate, approve
  (ADR-0019).
- **Users:** find an account by family code. See its players (name, age), each player's
  question history and progress, and the allowance. **Promote to unlimited** or remove it, with
  an audit log of who changed what and when.
- **Rename only, everywhere:** the admin app can't delete players or accounts either.

## Alternatives considered
- **Allow deleting players:** history would be lost or kept as orphan data, and it needs
  tombstones synced across devices. Deleting and adding a player again also gives that child
  new questions again. Rejected by the product owner.
- **Sign in with Apple as the account:** gives an identifier linked to the parent's Apple ID.
  It's more than we need. We can reconsider it if families want to use several Apple IDs.
- **Promo codes (App Store offer codes) instead of unlimited accounts:** these expire and are
  limited in number. An admin flag is simpler and has no end date.

## Consequences
- Simpler code now: no deletion path, no tombstone merging.
- A family that fills all 6 spots renames players instead of removing them.
- **Privacy change before accounts ship.** Sending player names and ages to our server changes
  ADR-0004, ADR-0020 and ADR-0023, the privacy policy, and the App Store privacy label (Kids
  Category). To do first:
  - Confirm with a COPPA and Australian Privacy Act check that a first name or nickname plus age
    is acceptable. Ask parents for a first name or nickname only.
  - Encrypt the data in transit and at rest.
  - Keep a process to erase an account on a parent's request (a legal right). This is the one
    allowed exception to "no deletion".
- `unlimited` must be checked by the app, which needs a network call. Offline, the app keeps the
  last known entitlement.

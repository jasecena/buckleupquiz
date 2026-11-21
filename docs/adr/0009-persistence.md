# 0009. SwiftData for players and stats, UserDefaults for settings

- **Status:** Accepted
- **Date:** 2026-11-22

## Context
The app needs to store settings, up to 6 player profiles, per-player stats and badges, and the
ids of questions each player has seen (so it can prefer unseen questions). A cloud copy may be
wanted later (ADR-0012).

## Decision
- **Settings:** one `Codable` `AppSettings` value stored as JSON in `UserDefaults`
  (`SettingsStore`). It's small and needs no migrations, and new fields get defaults.
- **Players, stats, seen questions (M5):** **SwiftData**. The models are designed to work with
  **CloudKit sync** from day one, even though sync is off in v1:
  - every property is optional or has a default
  - no `@Attribute(.unique)`
  - all relationships are optional
  
  Turning on iCloud sync later is then a container setting, not a migration.
- Persistence sits behind repository protocols (`PlayerRepository`, `StatsRepository`), so view
  models and tests don't depend on SwiftData directly.

## Alternatives considered
- **Core Data** — SwiftData is the modern API on iOS 17+ and has built-in CloudKit support.
- **GRDB / SQLite** — a third-party dependency (ADR-0004), and has no Apple-managed sync.

## Consequences
- Learning records (ADR-0016) for 1,500 questions are tiny, so they are stored as one JSON `Data` field per player.
- CloudKit-compatible modelling rules must be enforced in code review.

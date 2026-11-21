# 0016. Each player learns with Leitner boxes (spaced repetition)

- **Status:** Accepted
- **Date:** 2026-11-22
- **Amends:** FEATURES §4.4; [ADR-0015](0015-choice-questions-and-named-players.md) (seen ids → learning records); [ADR-0009](0009-persistence.md)

## Context
Product decision (2026-11-22): the quiz should help kids actually *learn* the answers, not just
hear each question once. Questions should come back on a schedule, a Leitner box: today,
tomorrow, then after 2, 4, 8 and 16 days. A wrong answer starts that question over. This is
per person: if Mia gets it wrong and Leo gets it right, only Mia hears it again. In one session,
each person is asked a question at most once, but different people may get the same question.

## Decision
- **Boxes and waits** (`Leitner.intervals = [0, 1, 2, 4, 8, 16]` days):

  | Box | Comes back after |
  |---|---|
  | 1 | today (a later session; never twice in one session) |
  | 2 | 1 day (tomorrow) |
  | 3 | 2 days |
  | 4 | 4 days |
  | 5 | 8 days |
  | 6 | 16 days |
  | learned | not asked again |

  A question met for the first time is in box 1 "today". **Right** → up one box. **Wrong** →
  back to box 1, due today. Right in box 6 → learned. Days are calendar days
  (`LearningDay`), so "tomorrow" means after midnight.
- **Per player.** Each `PlayerProfile` stores its own `LearningRecord` (question id → box and
  due day), JSON-encoded in `learningData` (CloudKit-friendly: one `Data` field with a default).
- **Selection order per turn** (`QuestionSelector`):
  1. questions **due** for this player, lowest box first;
  2. **new** questions (never asked to this player), preferring ones no other player got this
     session;
  3. in Parent mode, Talk About prompts again (they aren't boxed; fresh ones come first).

  Questions that aren't due yet, or are learned, are skipped. A player with nothing due and
  nothing new sits out; the setup screen shows "All done for today".
- **Knowing right from wrong in Listen mode.** Kids answer out loud in the car, so the app
  can't tell. After the answer is read, the screen shows **"Mia got it"** and **"Not yet"**.
  - "Not yet" sends the question back to box 1 for that player.
  - **No tap counts as heard, which is treated as right.** That way hands-free play still
    spaces questions out instead of repeating them forever.
  - Skipping *before* the answer is read leaves the boxes alone.
  - Voice answers (M5) will mark right or wrong automatically through `QuizSession.record`.
- **Question ids are permanent.** Records are keyed by id, so an id is never renumbered,
  moved to another topic or reused. `Content/retired-ids.json` lists removed ids, and the
  validator rejects them. Each topic has one id prefix.

## Alternatives considered
- **SM-2 / Anki-style ease factors.** These are more precise but need graded answers on a
  scale. Kids in a car give right or wrong at best, and the fixed doubling schedule was the
  one asked for.
- **Global repetition (one record per family).** This was rejected: the user asked for repeats
  to follow the person who got it wrong.
- **Ungraded = wrong (or "no change").** In hands-free play almost nothing gets tapped. With
  this rule the same questions would come back every session and never progress.

## Consequences
- Sessions can end early once a player's due and new questions run out. That's intended:
  the bank grows with content packs.
- Content edits must keep a question's meaning when it keeps its id (CONTENT.md).
- If the "No tap = right" default turns out wrong for families, it's one line in
  `ListenSessionModel`.

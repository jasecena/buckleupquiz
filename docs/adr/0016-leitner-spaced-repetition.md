# 0016. Each player learns with Leitner boxes (spaced repetition)

- **Status:** Accepted
- **Date:** 2026-11-22
- **Amends:** FEATURES §4.4; [ADR-0015](0015-choice-questions-and-named-players.md) (seen ids → learning records); [ADR-0009](0009-persistence.md)

## Context
Product decision (2026-11-22): the quiz should help kids actually *learn* the answers, not just
hear each question once. Questions should come back on a schedule, a Leitner box: today,
tomorrow, then after 2, 4, 8 and 16 days. A wrong answer starts that question over. This is
per person: if Mia gets it wrong and Leo gets it right, only Mia hears it again.

Follow-up (same day): it must stay **a game, not a drill**. Don't repeat a question on the same
day for anyone. Keep reviews to a small random share of each session, about 20%: 10% the
player's own reviews and 10% questions the *other* players had (yesterday first). Everything
else is new. Someone who is playing and hears another player get a question right moves
forward too. If that player got it wrong, the listener doesn't start over.

## Decision
- **Boxes and waits** (`Leitner.intervals = [0, 1, 2, 4, 8, 16]` days):

  | Box | Comes back after |
  |---|---|
  | 1 | the day it is met; nothing repeats the same day, so in practice the next day it is played |
  | 2 | 1 day (tomorrow) |
  | 3 | 2 days |
  | 4 | 4 days |
  | 5 | 8 days |
  | 6 | 16 days |
  | learned | not asked again |

  A question met for the first time is in box 1 "today". **Right** → up one box. **Wrong** →
  back to box 1. Right in box 6 → learned. **No question is played twice on the same day for
  anyone in the family**, so box 1 effectively means "tomorrow or later". Days are calendar
  days (`LearningDay`), so "tomorrow" means after midnight. Each card also stores `last`, the
  day it was last played.
- **Per player.** Each `PlayerProfile` stores its own `LearningRecord` (question id → box, due
  day, last day), JSON-encoded in `learningData` (CloudKit-friendly: one `Data` field with a
  default). Sessions get the **whole family's** records, so absent siblings count for "not
  twice a day" and for shared reviews.
- **Review mix, per player** (`ReviewMix`): each player's turns are planned as about **80% new,
  10% own reviews, 10% shared reviews**, at random spots, never the first turn. In a
  20-question game for two, each child gets 10 turns: 1 own review, 1 shared review and 8 new
  questions, so 4 of the 20 questions are reviews.
  - **Own review:** a random question that's due in this player's boxes.
  - **Shared review:** a question another family member played recently (last 7 days, the
    most recent day first, so usually yesterday). It must suit this player's age, and be new
    or due for them.
  - **New:** a question nobody in the family has had, else one new to this player.
  - If a kind runs out, the turn falls back (own ↔ shared → new; new → reviews). So reviews
    fill in once new questions run out, and every question eventually goes round the boxes.
- **Bystanders.** When a player's answer is right (or heard), every *other* player in the
  session who could get that question (same band, old enough) moves up a box for it too. When
  it's wrong, only the player who answered starts over; the others are left alone.
- **Talk About** prompts aren't boxed. Fresh ones come first, and they repeat only once all
  have been used.
- Review turns are introduced aloud ("Here's one from before. Do you remember?" / "This one
  came up for someone else. Let's see!") and labelled on screen, so they feel like a callback.
- A player with nothing left today sits out; if nobody can play a topic, Home says "That's
  everything for today".
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
- Most of each session is new, so it stays a game. Reviews are a light touch rather than a
  drill, and progress through all the boxes is slower but steady.
- Sessions can end early once a player's due and new questions run out. That's intended:
  the bank grows with content packs.
- Content edits must keep a question's meaning when it keeps its id (CONTENT.md).
- If the "No tap = right" default turns out wrong for families, it's one line in
  `ListenSessionModel`.

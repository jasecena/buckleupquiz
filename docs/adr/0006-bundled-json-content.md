# 0006. Bundled JSON content with a topic catalogue and CI validation

- **Status:** Accepted. Extended by [ADR-0031](0031-downloaded-question-updates.md): the same files are also published as signed downloads; the bundled set is the offline fallback.
- **Date:** 2026-11-22

## Context
The launch target is about 1,500 questions across 23 topics and 3 age bands, written and
reviewed by non-developers (parents, teachers, First Nations reviewers). Topics have metadata:
icon, colour, free or paid, age bands, and whether review is needed. The question schema is
fixed by FEATURES §4.1.

## Decision
- `Content/topics.json` is the **topic catalogue**. New topics are added as content, not code.
- `Content/questions/<topic>.json` holds one JSON array of questions per topic, using the
  FEATURES §4.1 schema. Files stay small, so diffs and reviews are per topic.
- The folder is bundled into the app as a folder reference and read through the `QuestionSource`
  protocol (`DirectoryQuestionSource`). A remote source can replace it later (ADR-0012).
- `scripts/validate_content.py` (standard-library Python) runs in CI and checks:
  - the schema and allowed values
  - duplicate ids and duplicate question text
  - open questions without `acceptedAnswers`
  - multiple-choice answers that aren't one of the options
  - option letters wrongly placed in `acceptedAnswers`
  - read-aloud time (about 2.5 words/s, max 12 s)
  - long answers
  - banned words in values and safety topics
  - `minAge` within its band

  `--strict` also enforces the launch targets for release builds.
- A Swift test loads the real `Content/` with the app's decoder, and checks that every
  question's own answer is accepted by the matcher. This stops the validator and the app
  from drifting apart.

## Alternatives considered
- **SQLite / Core Data seed** — not human-editable, so content can't be reviewed in PRs.
- **CMS or spreadsheet export** — may come later for authors, but JSON in git stays the source
  of truth that CI checks.

## Consequences
- 1,500 short questions is roughly 1 MB, which is negligible for app size.
- Values and safety topics are flagged `requiresReview`. The validator warns until that
  review has happened.

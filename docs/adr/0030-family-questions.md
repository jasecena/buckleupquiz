# 0030. Family questions: parents add their own, with on-device AI help and their own voice

- **Status:** Proposed (after launch)
- **Date:** 2026-11-22

## Context
Parents want to add their own questions: "What is Jenny's birthday?", "What's Mum's favourite
food?", "What street do we live on?". These are personal, which makes them special in a car
game, and also makes them sensitive. The product owner's brief (2026-11-22):
- A parent says a question to the phone, and the app helps turn it into a proper question with
  a few options. AI can help improve the wording.
- Optionally, the parent records their own voice for the question, so in the middle of a game
  it's suddenly Mum or Dad asking.
- "We don't store any of that information."

## Decision (proposed)
- **Local only.** Family questions and recordings stay on the phone. They are never sent to our
  server, never in error reports (ADR-0020: no question text, no answers), and never in the
  progress backup to our systems (there is none). A later CloudKit sync (ADR-0012) would use the
  family's own iCloud only.
- **AI on the device only.** Use Apple's on-device Foundation Models (iOS 26, Apple
  Intelligence iPhones) to suggest the wording and two plausible wrong options, and speech
  recognition on the device for dictation (as for answers, ADR-0018). No cloud AI: it would send
  a family's personal details to a third party, against ADR-0004 and the Kids Category rules.
  On phones without Apple Intelligence, the parent types or says the question and the options
  themselves.
- **The parent approves every question** before it's saved. The AI only suggests.
- **Same rules as our questions:** multiple choice with exactly 3 options, or true/false,
  answered by letter (ADR-0026); the same read-aloud limit and checks as `make validate`, run in
  the app. Each gets a permanent local id (e.g. `fam-<uuid>`), so the Leitner boxes work
  (ADR-0016).
- **Who it's for:** a family question can be for everyone or for chosen players (a question
  about Jenny isn't asked to Jenny). In a game, about 1 turn in 10 can be a family question,
  never the first one, like the review mix.
- **The parent's voice:** an optional recording of the question (and the options), played in
  place of the app's voice. Recorded only by a grown-up, behind the parental gate, stored on the
  phone, and deleted with the question. Children's audio is still never recorded (ADR-0004).
- **Behind the parental gate:** adding, editing and recording family questions is a Settings
  feature.

## Alternatives considered
- **Cloud AI (a server or an AI API)** — better on older phones, but it sends personal family
  details off the device, needs a privacy and Kids Category review, and costs money per use.
- **No AI, typed questions only** — simplest and fully private, and still the fallback. AI makes
  it much quicker to add a question while the idea is fresh.
- **Sharing family questions between families** — out of scope: they're personal by design.

## Consequences
- The privacy policy and the App Store privacy label must change before this ships: today the
  policy says audio is never recorded. Recordings would be the parent's own, on the device only.
- Family questions don't count against the daily allowance (ADR-0022). Whether the feature is
  part of BuckleUp Basic is still to be decided.
- Recordings make the app's storage grow; keep each one short (about 12 s, the question limit).
- Losing the phone loses family questions until a CloudKit sync exists.

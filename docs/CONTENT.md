# Writing questions

Questions live in `Content/questions/<topic>.json`, one JSON array per topic. Topics live in
`Content/topics.json`. Run `make validate` before every PR. CI runs it too.

## Question fields

| Field | Required | Notes |
|---|---|---|
| `id` | ✅ | `abc-0001`. The prefix is per topic; numbers are unique. Convention: `0001–0099` for 6–8, `0101–0199` for 9–10, `0201–0299` for 11–12 (extend with `1xxx` etc.) |
| `topic` | ✅ | an `id` from `topics.json` |
| `ageBand` | ✅ | `6-8`, `9-10` or `11-12` (must be one of the topic's bands) |
| `type` | ✅ | `multipleChoice` (exactly 3 options), `trueFalse`, or `talkAbout` (open discussion, Parent mode, no score, no time limit). No free-answer quiz questions ([ADR-0015](adr/0015-choice-questions-and-named-players.md)) |
| `question` | ✅ | must read aloud in ≤12 s (about 30 words, *including* options) |
| `options` | multipleChoice | **exactly 3** options. `null` for trueFalse and talkAbout |
| `answer` | quiz questions | must be one of `options` for multipleChoice; `"True"`/`"False"` for trueFalse; `null` for talkAbout |
| `acceptedAnswers` | — | other ways to say the *correct option* (`["hobart city"]`). **Never** put option letters here, because options are shuffled |
| `funFact` | — | one short sentence, read after the answer (can be turned off) |
| `explanation` | values topics | one *kind* sentence on why it's the good choice; always read |
| `difficulty` | — | 1–5 |
| `minAge` | — | only when a question fits the top of its band |
| `region` | — | `AU` for Australian content |

## Writing for the ear
- Every multiple-choice question gets **exactly 3 options**, each easy to say (knowledge topics: one to three words). Wrong options must be *plausible* (a real nearby city, a common misconception), never silly. Avoid options that sound alike, because kids answer by voice.
- Options are shuffled at runtime, so write them in any order.
- Write numbers in questions as words ("seven times eight") so the voice reads them naturally.
- True/false questions end with "True or false?"
- Read it aloud yourself. If you stumble, a kid will too.

## Values & safety topics (FEATURES §4.3, §4.5, §4.6)
- Reward the kind choice; never shame. Wrong options are *plausible* kid behaviour, never cruel
  or silly.
- No stereotypes (not even as a wrong option), no slurs, no politics, religion or current events.
- Every unsafe scenario ends with an action: **stop, block, tell a trusted adult**.
- Safety content follows eSafety Commissioner and ThinkUKnow guidance, using "safe adults"
  framing, not "stranger danger".
- All of this content needs parent or teacher review before release. First Nations content must
  be written or reviewed with Aboriginal and Torres Strait Islander input.

## Checks the validator runs
- Schema, ids and duplicates
- No `open` or `scenario` types; answers must be one of the options; exactly 3 options for multiple choice
- Read-aloud time and answer length
- Banned words in values and safety topics
- With `--strict`, launch targets: 60 per topic per band, and Manners with 40 scored + 20 Talk About per band

# 0019. Natural voices: pre-generated audio, downloaded 10 questions at a time

- **Status:** Proposed
- **Date:** 2026-11-22
- **Relates to:** [ADR-0004](0004-privacy-no-network-no-sdks.md) (needs an amendment), [ADR-0008](0008-audio-architecture.md), [ADR-0012](0012-future-backend.md), [ADR-0016](0016-leitner-spaced-repetition.md)

## Context
The on-device voice (`AVSpeechSynthesizer`) doesn't sound natural. The product direction
(2026-11-22) is:

- Every question is **pre-generated** with several natural voices and stored in the cloud.
  **No live text-to-speech API** is called from the app.
- In Settings, the family picks a voice. The app downloads audio for that voice
  **10 questions at a time**, plays it, and **deletes it once it's no longer needed**, so the
  app stays small and cleans up after itself.
- Later, each family's data syncs to the cloud (see "Open questions").

## Proposed decision

### 1. Generation (offline, in CI)
- A `scripts/voices/` pipeline (GitHub Actions, on content changes) turns every question into
  audio clips for every voice in `voices.json`. Each clip is keyed by a **content hash**, so
  only new or changed questions are regenerated, and stale clips are removed.
- **Provider:** run a listening bake-off first. Take 20 questions and 3 providers (Amazon Polly
  generative voices, which include en-AU; ElevenLabs; OpenAI TTS), and have kids and parents
  choose. Amazon Polly is the default candidate, since it's on AWS and its output may be
  stored and replayed. Check each provider's licence for **storing and redistributing**
  generated audio before choosing.
- **Per question, per voice:** `question` (question + options), `answer` ("The answer is… B,
  Hobart!") and `followup` (explanation or fun fact). Voice answers reuse `answer` for
  "Not quite, the answer was…" through a shared lead-in clip.
- **Phrase pack per voice** (downloaded once, kept): question numbers 1–100, intro and outro,
  cheers, "Time's up!", "Not quite, the answer was…", "this one's for you", streaks, score
  numbers (0–1000 in 5s), "points", badge names, Talk About lines. The text comes from
  `Phrases`, which stays the single source.
- **Format:** mono AAC (`.m4a`), about 32 kbps, so ~4 KB per second. A question's clips come to
  ~60 KB, a batch of 10 to ~0.6 MB, and a whole voice to ~90 MB at 1,500 questions. Nobody
  downloads a whole voice.

### 2. Names, which are dynamic and can't be pre-generated per family
- A **names pack** per voice holds the ~2,000 most common children's names (AU/UK/US).
  Requesting `names/mia.m4a` would tell the server a child's name, so the app downloads
  names in **first-letter buckets** (`names/m.zip`, about 1 MB). The server only learns a
  first letter.
- A name not in the pack is spoken by the on-device voice in that one spot. The alternative is
  leaving the name out of audio and showing it on screen ("This one's for you!").

### 3. Delivery (cloud)
- **Amazon S3 + CloudFront**, per the AWS default. CloudFront's always-free 1 TB/month of
  egress covers roughly 1.5 million 10-question batches. Paths are immutable:
  `voices/<voice>/<hash>.m4a`. A small signed `manifest-<voice>.json` maps question ids to
  hashes. Logging is off and there are no cookies.
- If egress ever outgrows the free tier, **Cloudflare R2** (no egress fees) is a drop-in
  replacement for the same files.
- Defined as code with AWS CDK in `infra/` (ADR-0012), with uploads done by the pipeline.

### 4. In the app
- **`SpeechOutput` plays segments.** `Phrases` gains a "speech plan" form: a list of segments,
  each a clip id with its text. The player plays the clip when it's cached and falls back to
  the on-device voice for that segment when it isn't. **Play never waits on the network.**
- **`VoicePackStore`** (in `Application Support`, excluded from backup):
  - downloads the phrase pack and the family's name buckets once per chosen voice;
  - keeps a **rolling buffer of the next 10 questions per selected player**. It refills
    in the background when it drops below 10, and fills up to 20 before a trip on Wi-Fi, so
    a 20-question game in a dead zone still has natural audio;
  - **deletes a question's clips** once the answer has been read and the turn is over.
    Leitner reviews come back days later and are re-downloaded then, since they're tiny.
  - deletes everything for the old voice when the voice changes.
- **Prefetch without guessing:** `QuestionSelector` already picks from candidates. It gains a
  tie-break that **prefers candidates whose audio is cached**. The store downloads the
  selector's top candidates for each player (due reviews, shared reviews and fresh questions),
  so what's played is almost always what was downloaded.
- **Settings → Voice:** a list of natural voices, each with a bundled 5-second sample, plus
  "iPhone voice (works offline)". Picking one starts the download, and a small status line
  says "Ready for the next 10 questions".

### 5. Privacy (needs ADR-0004 amended)
- Requests are **anonymous static GETs**: no account, no device id, no analytics, and no names
  (letter buckets only). The privacy label can stay **"Data Not Collected"**. The policy page
  will say the app downloads audio from our content server.
- No parental gate is needed for background content downloads. The gate still covers
  purchases and links.

## Open questions (for the product owner)
1. **"Synced to our global database about each user."** Children's data in a database we run
   brings in COPPA and Australian privacy law: verified parental consent, a different privacy
   label, a deletion process and security duties. ADR-0012 recommends syncing players,
   progress and scores through **CloudKit in the family's own iCloud**. That costs $0 and we
   never hold the data. Is a database we run needed, for example a parent web dashboard,
   Android, or our own analytics? If so, that's a separate ADR.
2. **Voices:** how many to launch with (suggested 3–4, at least one Australian), and which
   provider wins the bake-off.
3. **Names:** use the names pack, or leave names out of the audio?
4. Are natural voices **free or part of the Family Pass**?

## Rough costs (to verify at build time)
- Generation, one-off per voice: 1,500 questions × ~300 characters ≈ 0.45 M characters,
  roughly US$10–15 per voice on Polly generative voices. After that, only changed questions
  are regenerated.
- Storage: ~100 MB per voice, cents per month.
- Delivery: within CloudFront's free tier for a long time.

## Consequences
- A big jump in how the app sounds, with no live API cost and nothing to break mid-trip.
- The app gets its first network feature, so ADR-0004, the privacy policy and the review notes
  must change before release.
- Content edits trigger audio regeneration, so a content PR shows its audio diff in CI.
- `Phrases` must be built from a fixed set of segments so every spoken line can be
  pre-generated. Free-form sentences become clip sequences.

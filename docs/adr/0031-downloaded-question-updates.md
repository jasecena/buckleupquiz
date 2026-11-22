# 0031. New questions without an app update: signed question files downloaded from our CDN

- **Status:** Accepted (built for 0.4.0, before launch)
- **Date:** 2026-11-22
- **Refines:** [ADR-0012](0012-future-backend.md) (content packs: the static CDN option, for every iOS version)
- **Relates to:** [ADR-0006](0006-bundled-json-content.md) (bundled JSON, validator), [ADR-0021](0021-aws-infrastructure-terraform.md) (`api.buckleupquiz.com/content/`), [ADR-0016](0016-leitner-spaced-repetition.md) (permanent ids), [ADR-0022](0022-free-allowance-packs-and-basic-subscription.md) (allowance), [ADR-0025](0025-accounts-admin-and-rename-only-players.md) (admin app), [ADR-0004](0004-privacy-no-network-no-sdks.md) and [ADR-0020](0020-anonymous-error-telemetry.md) (privacy)

## Context
Until now every question was bundled in the app (ADR-0006). Adding or fixing one question meant
a new build, App Review (usually a day or two) and every family installing the update. The
product owner asked (2026-11-22) whether the questions should move to a database so more can be
added without an update, and decided to build it **before launch**: content will grow fast in
the first months (from 15 to 60 questions per age group), and fixes to facts shouldn't wait for
App Review.

What matters for this app:
- **It's played in a car.** Tunnels and country roads have no signal, so a game can never wait
  for the network.
- **It's a Kids Category app.** Each network call must be justified, carry no identifiers and be
  in the privacy policy.
- **Content is the product.** Every question is checked by `make validate` and reviewed in a pull
  request before families hear it. That must stay true for downloaded questions.
- The whole bank is small: about 1,500 short questions is roughly 1 MB (ADR-0006).

## Decision
**No live database.** Questions are published as **static, versioned, signed files** on our CDN.
The app downloads them in the background when it's online, keeps them on the phone, and always
plays from the phone. The bundled questions stay in the app as the offline fallback.

### The files
Under `https://api.buckleupquiz.com/content/v1/` (the content bucket and CloudFront from ADR-0021):
- `current.json`: `{"manifest": <base64 of the manifest's JSON>, "signature": <base64 Ed25519
  signature of those bytes>}`. One file, so a phone can never get a manifest without its
  signature, or the other way round. Cached for 5 minutes.
- The manifest (`ContentManifest` in QuizCore): `format` (1), `version` (only goes up: the Unix
  time of the commit the set was built from), `minAppVersion`, and every file with its SHA-256
  and size.
- `sets/<version>/topics.json` and `sets/<version>/questions/<topic>.json`: the same format and
  layout as `Content/` in the repo, so the existing `DirectoryQuestionSource` reads them. A set
  never changes once published (cached for a year).

### Publishing: the "Publish questions" workflow, run by hand
After the content pull request is merged (`.github/workflows/content-publish.yml`):
1. It refuses to run unless CI passed on that commit (content validation, the QuizCore tests, and
   the app's test that the matcher accepts every answer).
2. `make validate` again, then `scripts/publish_content.py` copies `Content/` byte for byte,
   writes the manifest and signs it. The private key is the GitHub secret
   `CONTENT_SIGNING_KEY`. Its public half is in `project.yml` (`CONTENT_PUBLIC_KEY`), so it's
   built into the app. `make content-signing-key` makes both, once.
3. It signs in to AWS with GitHub's OIDC token as `buckleupquiz-content-publisher` (bootstrap
   stack), a role that can only write under `content/` in the content bucket, and only from
   `main`. No AWS keys are stored in GitHub.
4. It uploads the set first and `current.json` last. If nothing changed since the last publish,
   it stops.

It's run by hand, not on every push: going live to every family is a deliberate step. To roll
back, revert the content commit and publish again (a newer commit, so a newer version). Later
the admin app (ADR-0025) writes to the repo or produces the same files; it never writes straight
to phones.

### In the app (`ContentUpdater`, `ContentStore`)
- **When:** after launch and whenever the app comes back to the screen, at most once every 12
  hours. Downloads are in the background and the app never waits for them. If there's no signal,
  it tries again next time, and says nothing.
- **How:** an ephemeral `URLSession` (no cookies, no cache), a plain GET with no ids, names,
  counts or device details. Only files whose SHA-256 changed are downloaded; the rest are copied
  from the set already on the phone.
- **Checks before use:** the signature (CryptoKit, in the app, since QuizCore stays
  Foundation-only), the manifest's format, `minAppVersion`, safe file names (only `topics.json`
  and `questions/<name>.json`, so nothing can be written elsewhere), each file's size and
  SHA-256, and then a full load with `DirectoryQuestionSource`, which already rejects unknown
  topics and duplicate ids. If any check fails, the new set is thrown away, the last good set
  stays, and one anonymous error report says which check failed (ADR-0020).
- **Which set plays:** the newest good set. The bundled set has its own version
  (`BUQContentVersion`, the commit time, set by the release workflow), so an app update with
  newer bundled questions wins over an older download. If a downloaded set can't be read at
  launch, the bundled set is used (`FallbackQuestionSource`).
- **When it changes:** a new set replaces the bank for the next game. A game already playing
  keeps the questions it started with.
- **Storage:** Application Support/DownloadedContent, left out of the device backup (it can be
  downloaded again). Only the current set is kept.
- **Off switch:** a build with no content URL or public key plays only its bundled questions.

### Rules for question ids
- Ids are **permanent and never reused** (ADR-0016). A question can be edited (wording, a fixed
  fact) and keep its id. A question with a different meaning gets a new id.
- Removing a question just leaves it out of the next set. A player's Leitner history and the
  family's allowance may still name it; question selection only looks at questions in the bank,
  so those ids are ignored.
- A new question is a new id, so the allowance (ADR-0022) counts it like any other.

### What still needs an app update
- New question kinds or fields the app can't read (that's what `minAppVersion` is for: older apps
  keep their current set and say nothing).
- New in-app purchases: a paid pack's product must exist in App Store Connect and be known to the
  app. New free topics and new questions in existing topics need no update.

### Privacy
- The download sends nothing about the family. CloudFront keeps no access logs (ADR-0021).
- The privacy label doesn't change (no data is collected). The privacy policy says the app
  downloads question updates from our server, and `CLAUDE.md` names it as the second network
  call.

## Alternatives considered
- **A live database or API, asked during the game:** needs signal in a moving car, adds a server
  that can go down, and every request is a call to justify in a kids' app. It's also more to
  build and run for 1 MB of mostly static text.
- **Apple-hosted Background Assets** (ADR-0012's first choice): needs iOS 26, and the app
  supports iOS 17. Worth revisiting once iOS 17–25 users are few. The files above can move there
  without changing the format.
- **CloudKit public database:** free, but questions become records edited in the CloudKit
  console or by custom tooling, away from the JSON files that pull requests review and CI checks.
- **A manifest and a separate signature file:** with caching, a phone could get a new signature
  with an old manifest for a few minutes and refuse a good set. One file avoids that.
- **Stay bundled only:** the simplest, and still the fallback. But every content fix waits for a
  build and App Review, and families who don't update never get it.

## Consequences
- Adding or fixing questions becomes: pull request, CI green, merge, run "Publish questions".
  Families get them within about 12 hours of opening the app, with no update.
- The app still works with no signal, ever: the bundled set is always there.
- A bad set can't reach a game: unsigned, changed, unreadable or too-new files are refused.
- The bundled set should still be refreshed in each app release, so new installs start current.
- One-time setup by the owner: `make content-signing-key`, `make infra-bootstrap` (adds the
  publisher role), and the GitHub variable `CONTENT_PUBLISH_ROLE_ARN` (docs/RELEASING.md).
- Losing the signing key means making a new one and an app update. Apps with the old key keep
  their last set until they update.
- Natural voice packs (ADR-0019) can reuse the same manifest, signature and downloader.

# Product progress

A plain-language view of what's done and what's left. The detailed engineering checklist is
[STAGES.md](STAGES.md), and the decisions are in [adr/](adr/).

**Last updated:** 2026-11-22. **Latest build:** v0.3.5 (build 9) on TestFlight.

## Where we are
The app plays a full hands-free game in the car: it reads questions, listens for answers, keeps
score per child and remembers what each child has learned. It is on TestFlight for the family.
The website, domain and anonymous error reports are live on AWS. Paid features are built, and
the App Store agreement, banking and tax are done; they can be sold once the products are created
in App Store Connect.

## Done

### Playing
- Topic grid. One tap starts a game with the players and length from last time.
- Named players (up to 6), each getting questions for their own age.
- Every player gets the same number of questions, planned before the game starts. Games are 5, 10
  or 15 questions each, 50 at most. No Endless mode.
- The app reads the question and all the options, then listens straight away for 6 s, with a
  tick sound and a countdown.
- A child answers with the letter: A, B or C (or "true" / "false"). "Correct!" is only said
  for the right letter; the answer's words are never checked, so a wrong answer is never called
  right (ADR-0026). If nothing clear is heard, the answer is shared and the game moves on.
  There is never a "wrong" sound or "not quite".
- "Mia, this one's for you!" on each player's first turn, then just "Mia."
- Skip before the answer gives the same player a new question.
- Scoreboard during the game (can be turned off). Scores are read out at the end, with streaks
  and badges.
- Talk About prompts (Parent mode, off by default, 30 s timer).
- Background play: asked the first time the app goes to the background.

### Learning
- Leitner boxes per player: questions come back after 1, 2, 4, 8 and 16 days. A wrong answer
  starts the question over. An unheard answer counts as remembered.
- Each game is about 80% new questions, 10% the player's own reviews, and 10% questions a
  brother or sister had recently.
- 211 questions across Animals, Geography, Maths, Space and Manners.

### Accounts and data
- Progress survives deleting and reinstalling the app, through iCloud and the Keychain. There's
  no sign-in and no personal id.
- Each player's question history is kept and backed up.
- **Players can only be renamed, never deleted (new in 0.3.6).**

### Money (built; not yet on sale)
- Free: Animals and Geography, 30 questions each, plus 2 more each day the app is opened.
  Manners has 10.
- Question packs: 50 questions for A$0.99.
- BuckleUp Basic: A$4.99/month. Gives 10 topics, 40 new questions each day the app is opened,
  6 players and fixing scores. No free trial.
- Out of questions: 0–2 each blocks the game, 3–4 each warns, 5 each is the minimum.
- Parental gate in front of purchases. TestFlight-only switch to try Basic.
- TestFlight-only **Reset all data** button for testers: back to a fresh install, including the
  iCloud and Keychain backup (ADR-0027).
- Paid Applications agreement accepted, with banking and tax. Launch prices agreed.

### Reliability and support
- Mic check screen with fix guides for known problems (for example, Dictation turned off).
- Anonymous error reports to our own server (api.buckleupquiz.com): no names, answers or ids.
- Automatic tests on every change. Tagging a version uploads it to TestFlight.

### Infrastructure
- buckleupquiz.com (Route 53 DNS), HTTPS website, report endpoint, all in Terraform, least
  privilege, low cost. Domain contact verified, and the domain is verified in App Store Connect.

## Waiting on you
- [ ] Choose which simplifications to make (see "Simplify" below).
- [ ] Natural voices: how many voices to launch with and which ones (after a listening test with
      the kids), and whether children's names are spoken in the natural voice (ADR-0019).
- [ ] Sponsor messages: find sponsors (or use a message about Basic instead), and get a legal and
      App Review check of the flow before it's built (ADR-0024).
- [ ] Accounts: a privacy check (COPPA and the Australian Privacy Act) that a first name or
      nickname plus age is fine to keep on our server (ADR-0025).
- [ ] Backend: accept the backend plan when that work is scheduled. It is still only a proposal
      (ADR-0012).

## Remaining before launch
- [ ] **Simplify** the features listed below, to cut crash risk.
- [ ] Create the subscription and packs in App Store Connect (price, description and a review
      screenshot each; turn on Family Sharing for Basic), then test buying in the sandbox
      (ADR-0022).
- [ ] Locked topics enforced, and mixed-topic games for Basic (ADR-0017, ADR-0022).
- [ ] Questions for Aussie History, Science, Sport, Food and a second values topic, so Basic's
      10 topics all play. Target about 60 per topic per age group.
- [ ] Parent or teacher review of the values and safety questions.
- [ ] Real-car tests: 3 or more cars plus CarPlay, road noise, kids. Tune listening and speech
      speed (ADR-0008, ADR-0018).
- [ ] Record about 100 real answers (quiet and with road noise) and turn them into tests for
      letter matching (ADR-0007, ADR-0026).
- [ ] Phone-call interruption and a 20-question locked-screen game on a real device.
- [ ] Onboarding: welcome, a 3-question demo, add the first player. Teach "say the letter"
      (ADR-0026), and explain that some cars show a phone-call screen while the mic is on
      (ADR-0008).
- [ ] Mascot, app icon, sounds and App Store screenshots.
- [ ] App Store listing: description (it must explain the subscription), age rating, Kids
      Category age band and App Review contact details (ADR-0022).
- [ ] Parental gate before settings, links and support email.
- [ ] Accessibility pass (text size, VoiceOver) and iPad layout.
- [ ] Privacy label (Diagnostics, not linked), final privacy policy, name and trademark check
      (ADR-0020).
- [ ] Network check: the app only talks to api.buckleupquiz.com, and only sends anonymous error
      reports (ADR-0004, ADR-0020).
- [ ] Build with Xcode 27 before April 2027.

## After launch
- [ ] **Free access for chosen people** with Apple offer codes for BuckleUp Basic (made in App
      Store Connect), never our own codes (ADR-0027).
- [ ] **Natural voices** (ElevenLabs): plans and costs agreed (ADR-0019).
- [ ] **Progress screen for parents**: what each child has learned.
- [ ] **Sponsor messages** for extra free questions, opt-in, never in Basic (ADR-0024).
- [ ] **Accounts and admin app** (ADR-0025):
  - **Account data:** only an account id, plus each player's name and age.
  - **Question history:** kept per player, within each account.
  - **Admin app:** manage questions, voices and users.
  - **Promote to unlimited:** turn on unlimited for chosen accounts without a subscription.
    Do not build yet. Until then, free access is TestFlight now and Apple offer codes after
    launch, never our own unlock codes or device ids (ADR-0027).
  - **No deleting:** players and accounts can only be renamed. The one exception is erasing an
    account when a parent asks, which is a legal right.
  - **Before this ships:** a privacy check.
- [ ] **Question packs downloaded** instead of all bundled in the app, so the app stays small
      (ADR-0012).
- [ ] **Players synced through the family's iCloud (CloudKit)**, needed once the backup passes
      1 MB (ADR-0012, ADR-0023).
- [ ] **A bigger plan** (for example "Plus", with more questions a day for long trips), in the
      same subscription group (ADR-0022).
- [ ] **Kids' plug-in microphones**, if phone and car microphones aren't good enough (ADR-0018).
- [ ] Remove the unused `acceptedAnswers` from the question files (ADR-0026).

## Simplify
Some features changed direction after they were built, and left extra code paths behind. Fewer
paths means fewer ways to crash. Recommended, most valuable first:

| # | What | Why it's complicated | Proposal | Risk to remove | Decision |
|---|---|---|---|---|---|
| 1 | Second speech engine (iOS 26 SpeechAnalyzer) used when Dictation is off | Added to work around Dictation being off. It is a separate 180-line engine that has never been checked on a phone. | Remove it, and show the "Turn on Dictation" guide instead (already built). | Low. Families with Dictation off follow a one-time guide. |
| 2 | Trying 9 English accents in turn, with retries | Every listen can cycle through recognisers and restart up to 14 times. | Use one recogniser (the phone's English, or en-AU) and listen once per turn. | Low |
| 4 | Talk About with its own timer and voice commands while chatting | A separate mode with its own timer task and listening loop. It's off by default and only works with a grown-up. | Remove it from v1, and bring it back as a simple timed prompt later. | Medium: a values feature parents may like. |
| 5 | Two answer modes (tap "Got it" vs voice) | Two scoring paths through the same game. | Keep voice, and keep "just listen" (no scoring) as the fallback. Drop tapping "Got it" and "Not yet". | Medium |
| 6 | 80/10/10 review mix with brothers' and sisters' questions | Three kinds of turns with fallbacks between them. | Keep the Leitner boxes. Drop only the brothers' and sisters' questions: each player gets their own due reviews first, then new questions. | Low for kids; less variety. | Thinking it over |
| 7 | Skip gives the same player an extra question from outside the plan | Picks questions after the game is planned, and spends allowance mid-game. | Skip moves on to the next planned question for the same player. | Low |
| 8 | Endless leftovers | Dead constant. | Removed in 0.3.6. | None | Done |
| 9 | Player deletion | Tombstones synced across devices. | Removed in 0.3.6 (rename only). | None | Done |

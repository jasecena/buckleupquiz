# Product progress

A plain-language view of what's done and what's left. The detailed engineering checklist is
[STAGES.md](STAGES.md), and the decisions are in [adr/](adr/). Every list is ordered with the
quickest wins first.

**Last updated:** 2026-11-22. **Latest build:** v0.3.6 (build 10) on TestFlight.

## Where we are
The app plays a full hands-free game in the car: it reads questions, listens for answers, keeps
score per child and remembers what each child has learned. It is on TestFlight for the family.
The website, domain and anonymous error reports are live on AWS. Paid features are built, and
the App Store agreement, banking and tax are done; they can be sold once the products are created
in App Store Connect.

## What's new in 0.3.6

### New features
- **Reset all data** for testers (Settings → Testing, TestFlight only): back to a fresh install,
  including the iCloud and Keychain backup. Purchases stay with the Apple ID (ADR-0027).

### Changes and fixes
- **Answers are the letter only:** A, B or C, or "true" / "false". "Correct!" is only said for
  the right letter, and the answer's words are never checked, so a wrong answer is never called
  right. If the recogniser isn't sure which letter it heard, it keeps listening (ADR-0026).
- The tip at the start of a game now says "Say the letter, A, B or C, as soon as you know it!",
  and the note in Settings → Answers no longer mentions a beep.
- Players can only be renamed, never deleted (ADR-0025).
- Clean-up: the listening time is fixed (leftover "moving deadline" code removed), and Endless
  mode leftovers are gone. Nothing you see changes.

## Decisions for you

### Easy (a quick yes or no)
Each removes extra code that can go wrong. All are low risk, and recommended.
- [ ] **Remove the second speech engine** (the iOS 26 one used when Dictation is off). It's 180
      lines that have never been checked on a phone. Families with Dictation off get the "Turn on
      Dictation" guide instead, which is already built.
- [ ] **Use one recogniser and listen once per turn**, instead of trying 9 English accents with
      retries (up to 14 restarts per listen).
- [ ] **Skip moves on to the next planned question** for the same player, instead of picking an
      extra question mid-game (which also spends the day's allowance mid-game).

### Hard (need more thought, or someone else)
- [ ] **Review mix** (you're thinking it over): keep the Leitner boxes either way. The choice is
      whether to drop only the 10% brothers' and sisters' questions, so each player gets their
      own due reviews first, then new questions. Less variety, simpler code.
- [ ] **Two answer modes:** keep voice and "Just listen", and drop tapping "Got it" / "Not yet"?
      Medium risk: two scoring paths today.
- [ ] **Talk About:** remove it from v1 and bring it back later as a simple timed prompt? It has
      its own timer and listening loop, but parents may like it.
- [ ] **Natural voices:** how many voices to launch with and which ones (after a listening test
      with the kids), and whether children's names are spoken in the natural voice (ADR-0019).
- [ ] **Accounts:** a privacy check (COPPA and the Australian Privacy Act) that a first name or
      nickname plus age is fine to keep on our server (ADR-0025).
- [ ] **Sponsor messages:** find sponsors (or use a message about Basic instead), and get a legal
      and App Review check of the flow before it's built (ADR-0024).
- [ ] **Backend:** accept the backend plan when that work is scheduled. It is still only a
      proposal (ADR-0012).

## To do before launch

### Quick (clicks in App Store Connect, or a small change)
- [ ] Create the subscription and packs in App Store Connect (price, description and a review
      screenshot each; turn on Family Sharing for Basic), then test buying in the sandbox
      (ADR-0022).
- [ ] App Store listing: description (it must explain the subscription), age rating, Kids
      Category age band and App Review contact details (ADR-0022).
- [ ] Privacy label (Diagnostics, not linked) and the final privacy policy (ADR-0020).
- [ ] Parental gate before settings, links and support email (the gate already exists for
      purchases).
- [ ] Network check: the app only talks to api.buckleupquiz.com, and only sends anonymous error
      reports (ADR-0004, ADR-0020).
- [ ] Build with Xcode 27 before April 2027 (a setting, once GitHub has it).

### Medium (a few days of work, or tests on a real phone)
- [ ] Locked topics enforced, and mixed-topic games for Basic (ADR-0017, ADR-0022).
- [ ] Phone-call interruption and a 20-question locked-screen game on a real device.
- [ ] Onboarding: welcome, a 3-question demo, add the first player. Teach "say the letter"
      (ADR-0026), and explain that some cars show a phone-call screen while the mic is on
      (ADR-0008).
- [ ] Accessibility pass (text size, VoiceOver) and iPad layout.
- [ ] Name and trademark check.

### Big (weeks, or needs other people)
- [ ] Real-car tests: 3 or more cars plus CarPlay, road noise, kids. Tune listening and speech
      speed (ADR-0008, ADR-0018).
- [ ] Record about 100 real answers (quiet and with road noise) and turn them into tests for
      letter matching (ADR-0007, ADR-0026).
- [ ] Mascot, app icon, sounds and App Store screenshots.
- [ ] Parent or teacher review of the values and safety questions.
- [ ] Questions for Aussie History, Science, Sport, Food and a second values topic, so Basic's
      10 topics all play. Target about 60 per topic per age group.

## After launch
- [ ] **Free access for chosen people** with Apple offer codes for BuckleUp Basic (clicks in App
      Store Connect), never our own codes (ADR-0027).
- [ ] Remove the unused `acceptedAnswers` from the question files (ADR-0026).
- [ ] **Progress screen for parents**: what each child has learned.
- [ ] **A bigger plan** (for example "Plus", with more questions a day for long trips), in the
      same subscription group (ADR-0022).
- [ ] **Players synced through the family's iCloud (CloudKit)**, needed once the backup passes
      1 MB (ADR-0012, ADR-0023).
- [ ] **Question packs downloaded** instead of all bundled in the app, so the app stays small
      (ADR-0012).
- [ ] **Natural voices** (ElevenLabs): plans and costs agreed (ADR-0019).
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
- [ ] **Kids' plug-in microphones**, only if phone and car microphones aren't good enough
      (ADR-0018).

## Done (what the app does today)

### Playing
- Topic grid. One tap starts a game with the players and length from last time.
- Named players (up to 6), each getting questions for their own age.
- Every player gets the same number of questions, planned before the game starts. Games are 5, 10
  or 15 questions each, 50 at most.
- The app reads the question and all the options, then listens straight away for 6 s, with a
  tick sound and a countdown.
- Answers by letter (see 0.3.6). There is never a "wrong" sound or "not quite": if nothing clear
  is heard, the answer is shared and the game moves on.
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
- Each player's question history is kept and backed up. Players can only be renamed.

### Money (built; not yet on sale)
- Free: Animals and Geography, 30 questions each, plus 2 more each day the app is opened.
  Manners has 10.
- Question packs: 50 questions for A$0.99.
- BuckleUp Basic: A$4.99/month. Gives 10 topics, 40 new questions each day the app is opened,
  6 players and fixing scores. No free trial.
- Out of questions: 0–2 each blocks the game, 3–4 each warns, 5 each is the minimum.
- Parental gate in front of purchases.
- Paid Applications agreement accepted, with banking and tax. Launch prices agreed.

### Testing
- TestFlight builds have a switch to try Basic, and Reset all data. Free access follows the
  standard path: TestFlight now, Apple offer codes after launch (ADR-0027).

### Reliability and support
- Mic check screen with fix guides for known problems (for example, Dictation turned off).
- Anonymous error reports to our own server (api.buckleupquiz.com): no names, answers or ids.
- Automatic tests on every change. Tagging a version uploads it to TestFlight.

### Infrastructure
- buckleupquiz.com (Route 53 DNS), HTTPS website, report endpoint, all in Terraform, least
  privilege, low cost. Domain contact verified, and the domain is verified in App Store Connect.

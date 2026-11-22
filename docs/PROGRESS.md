# Product progress

A plain-language view of what's done and what's left. The detailed engineering checklist is
[STAGES.md](STAGES.md), and the decisions are in [adr/](adr/). Every list is ordered with the
quickest wins first.

**Last updated:** 2026-11-22. **Latest build:** v0.3.8 (build 12) on TestFlight. 0.3.9 is ready to publish.

## Where we are
The app plays a full hands-free game in the car: it reads questions, listens for answers, keeps
score per child and remembers what each child has learned. It is on TestFlight for the family.
The website, domain and anonymous error reports are live on AWS. Paid features are built, and
the App Store agreement, banking and tax are done; they can be sold once the products are created
in App Store Connect.

## What's new in 0.3.9

### New features
- **"New game" by voice:** when the app has been hearing the players well in the car, the
  ending says "If you'd like to play some more, just say "new game"!" and listens for 10
  seconds. "New game", "play again" or "one more" starts the same topic and players again.
  - Only offered when listening has worked: a voice game, the app on screen, at least one
    answer heard, and no more than 2 missed. Otherwise it says to start a new game by tap.
  - "No" always wins, and cheers ("Yes, I won!") or chatter never start a game.
  - Not offered after "stop", or when there aren't enough questions left today.
  - The finished screen has a **Play again** button too, for any game.

### Changes and fixes
- **No winner when the scores can't be trusted:** a voice game that went to the background, or
  where more than 2 answers weren't heard, ends with "Great job, Mia and Leo!" instead of the
  scores and the winner. Points still count towards badges.
- The scores show on screen while the ending is read out (it showed "Buckle up…" before).
- **One speech engine:** the untested iOS 26 fallback for phones with Dictation off is gone.
  Those families see the "Turn on Dictation" guide in Mic check, as before.
- **Two recognisers instead of nine:** the phone's English (or Australian English) and a US
  English backup. Listening still restarts if it stops early, so late answers are heard.

## What's new in 0.3.8

### Changes and fixes
- **Voice answers need the app on screen.** In 0.3.7 the mic stayed on with the screen locked,
  but nothing was heard: Apple's speech recognition doesn't work in the background (ADR-0029).
  - **Screen stays on:** during a voice game the screen doesn't lock by itself, so keep the phone
    in a cradle with the app open (and charging).
  - **In the background** (screen locked by hand, or another app open) the mic is off (no
    orange dot) and the answers are read out, as in "Just listen".
  - **Back on screen** it listens again from the next question.

## What's new in 0.3.7

### New features
- **20 questions each** is now a game length, next to 5, 10 and 15. A game still has at most 50
  questions, so 3 or more players get fewer each (3 players: 16 each).
- **Variety between questions:** before each question except the first, the app picks at random
  1–2 seconds of quiet, a short line ("Thinking caps on!") or a little tune. Long or hard
  questions are sometimes read twice ("Once more…").

### Changes and fixes
- The microphone stays on for the whole game (ADR-0028), but this didn't make answers heard
  with the screen locked (see 0.3.8).
- If the microphone is busy for one answer (a phone call), the game tries again on the next
  question, instead of stopping listening for the rest of the game.
- **After a phone call** the app takes the audio and the mic back before carrying on.
- **A forgotten pause** turns the mic off after 5 minutes. Play turns it back on. The mic is
  always turned off when a game ends.
- **The ending is clearer:** "That's the end of the game! That was 15 questions each. … If you'd
  like to play some more, start a new game!" It said "end of the ride", which sounded like the
  car trip. The number is what was really played: when there aren't enough new questions left
  today, a game can be shorter than chosen.

## Decisions for you

### Easy (a quick yes or no)
Each removes extra code that can go wrong. All are low risk, and recommended.
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
      (ADR-0026), explain that some cars show a phone-call screen while the mic is on
      (ADR-0008), and that voice answers need the app on screen, ideally in a cradle (ADR-0029).
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
- Every player gets the same number of questions, planned before the game starts. Games are 5, 10,
  15 or 20 questions each, 50 at most.
- The app reads the question and all the options, then listens straight away for 6 s, with a
  tick sound and a countdown.
- Answers by letter: A, B or C, or true / false (ADR-0026). There is never a "wrong" sound or
  "not quite": if nothing clear is heard, the answer is shared and the game moves on.
- "Mia, this one's for you!" on each player's first turn, then just "Mia."
- Skip before the answer gives the same player a new question.
- Variety between questions (quiet, a short line or a tune), and long or hard questions sometimes
  read twice.
- The ending says how many questions were played and invites a new game. When the app has
  been hearing the players, they can just say "new game"; otherwise tap Play again.
- Voice answers while the app is on screen; the screen stays on during a voice game. In the
  background the answers are read out (ADR-0029).
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

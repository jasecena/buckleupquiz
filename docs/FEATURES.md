# BuckleUp Quiz — v1 Feature List

> **BuckleUp Quiz** — a hands-free, voice-first educational quiz for kids aged 6–12, built for car trips and home. The app reads a question aloud, waits, then reveals the answer. The paid tier listens for spoken answers, takes turns between named players and keeps score.

> **Changes since this spec was written** (see [ADR-0015](adr/0015-choice-questions-and-named-players.md)):
> - Every quiz question is a single choice: **3 options**, or true/false. "Scenario" is merged into multiple choice. Open discussion questions stay as **Talk About** prompts (Parent mode, off by default) with **no time limit**: the app waits until the family presses Next.
> - Families add players with a name and age. Sessions start with "Who's playing?" instead of an age-band picker, and each child gets questions for their own age.
> - Parent mode has its own Settings section and a **separate talk timer** (default 30 seconds; No limit is an option). Parent mode itself is off by default.
> - Questions repeat per player with **Leitner boxes**: today, tomorrow, then after 2, 4, 8 and 16 days. A wrong answer starts over, for that player only. Reviews are about 20% of a session (10% own, 10% from what the others had), nothing repeats on the same day, and the rest is new ([ADR-0016](adr/0016-leitner-spaced-repetition.md)).
> - **Hands-free voice answers** are the default: after a beep, whoever's turn it is says the answer, and the app judges it, keeps score and reads the scoreboard at the end. If nobody is heard it falls back to reading answers out ([ADR-0018](adr/0018-hands-free-voice-answers.md)).
> - **One tap to play:** who's playing and the length are remembered. Home has a big **Play** button (random topic), and tapping a topic starts it straight away. Setup appears only before the first game or via **Change** ([ADR-0017](adr/0017-one-tap-start.md)).

---

## 0. Branding

- **App name:** BuckleUp Quiz (always written as one word "BuckleUp", with a capital U, then "Quiz").
- **App Store title (≤30 chars):** `BuckleUp Quiz: Kids Car Games`
- **App Store subtitle (≤30 chars):** `Voice trivia, manners & safety`
- **Xcode project / target:** `BuckleUpQuiz`. **Bundle ID:** `com.<yourcompany>.buckleupquiz`.
- **Spoken intro (TTS) when a session starts:** "Buckle up, kids… question one!"
- **Spoken outro:** "That's the end of the ride! Here are the scores…"
- **Tagline for ads:** "Turn 'are we there yet?' into 'ask me another!'"
- **Visual identity:** a friendly, original mascot (not a seatbelt logo, to stay clear of existing "Buckle Up" road-safety campaign branding). Bright, high-contrast colours, and big rounded type.
- **Before launch:** check the name with IP Australia, and register the `.com.au` and `.app` domains and the Instagram and TikTok handles.

---

## 1. Platform & Tech Constraints

- **Platform:** iOS 17+ (iPhone first, iPad compatible). Android is out of scope for v1.
- **UI:** SwiftUI.
- **Text-to-speech:** `AVSpeechSynthesizer` (on-device, free). Use an Australian English voice (`en-AU`) by default.
- **Speech recognition:** Apple `Speech` framework (`SFSpeechRecognizer`) with `requiresOnDeviceRecognition = true`. No audio leaves the device.
- **Payments:** StoreKit 2.
- **Data:** a bundled JSON question bank inside the app. **No backend, no accounts.** The only network call is anonymous error reports (ADR-0020).
- **Persistence:** SwiftData or `UserDefaults` for players, scores and settings. Optional iCloud sync is out of scope.
- **Analytics/ads:** none. This is required for Apple's Kids Category.
- **Architecture:** MVVM, with a separate `QuizEngine` (pure Swift, unit-testable) and an `AudioService` (TTS + speech recognition + audio session).

---

## 2. Free Tier (MVP)

### 2.1 Topic ("area") selection
- Home screen shows a grid of big topic tiles, for example: Animals, Geography, Space, Maths, Aussie History, Science, Sport, Food, **Manners & Friendship** (see 4.3).
- **The free tier unlocks 3 topics**, and the rest show a lock icon. Consider making Manners & Friendship one of the free topics, because it's a strong selling point for parents.
- Each tile shows an icon, the topic name and the question count.
- User picks a topic, then **who's playing** (named players with ages; each gets questions for their own age band: 6–8, 9–10 or 11–12). *(Changed by ADR-0015: originally an age-band picker.)*
- **Everyone gets the same number of questions.** The game length is rounded to a multiple of the players (10 questions with 3 players = 3 each). A skipped question doesn't count. If someone runs out of questions mid-game, the game ends there.
- **Up to 2 players per game for free.** Games with 3–6 players need the Family Pass (product decision, 2026-11-22). Anyone can create up to 6 player profiles.

### 2.2 Listen mode (no voice input)
Game loop per question:
1. App reads the question aloud, plus the multiple-choice options if the question has them.
2. App waits for a **configurable "think time"** (default 6 seconds, range 3–20). A soft tick plays ("ding, ding, ding"), and in voice mode the app listens during it.
3. App says "The answer is… **X**" plus an optional one-line fun fact.
4. Short pause (2 seconds), then the next question plays automatically.
- **Session length:** 10, 20 or 30 questions, or Endless.
- **On-screen:** large question text, a countdown ring, and the revealed answer. The screen is readable but never required.
- **Controls:** big Pause/Resume, Skip and Repeat buttons. Also support the play/pause/next buttons on headphones and the car steering wheel via `MPRemoteCommandCenter`.

### 2.3 Hands-free, car-friendly audio
- Audio plays through car Bluetooth or CarPlay audio, or AirPods.
- **Background audio mode:** the quiz keeps running with the screen locked.
- Shows lock-screen "Now Playing" info (topic and question number) via `MPNowPlayingInfoCenter`.
- Handles interruptions such as phone calls and navigation prompts: it pauses, then resumes or repeats the current question.
- Lowers the volume of music already playing instead of stopping it, configurable in Settings.

### 2.4 Car Bluetooth microphone and speakers (hands-free, like a phone call) — v1
Goal: kids answer through the **car's built-in microphone**, and the app talks through the **car speakers**, the same way a hands-free phone call works.

**Audio session**
- Voice mode (paid) sets `AVAudioSession` to category `.playAndRecord`, mode `.voiceChat` (or `.default` combined with voice processing; test both), with options `[.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker, .duckOthers]`.
  - `.allowBluetooth` turns on the Bluetooth **hands-free (HFP)** connection, which gives access to the car's microphone and speakers.
  - When the car isn't connected, it falls back to the iPhone's built-in mic and speaker.
- Listen mode (free, no mic) uses `.playback` over **A2DP**, the high-quality music link.
- **Never switch between HFP and A2DP during a session.** Switching causes 1–3 second gaps and clipped speech on many car stereos. Pick the mode when the session starts and keep it until the session ends.
- Choose the input device explicitly: find the Bluetooth HFP input in `availableInputs` and call `setPreferredInput(_:)`. Show the active device on screen, for example "🎤 Using: Toyota Yaris".
- With **CarPlay**, input and output go to the car automatically under the same session settings.

**Echo and noise**
- Turn on `AVAudioEngine.inputNode.setVoiceProcessingEnabled(true)` to get Apple's echo cancellation and noise suppression. This stops the mic picking up the app's own voice coming out of the car speakers.
- **One direction at a time:** never listen while the app is speaking. Speak, wait 300 ms, play the listening chime, then open the mic.
- Configurable silence detection: stop listening after about 1.2 seconds of silence once speech has started.

**Behaviour and edge cases**
- HFP sound is lower quality (mono, 16 kHz wideband or 8 kHz narrowband on older cars). Tune the TTS voice and rate for clarity, and test answer matching on audio recorded at 8 kHz.
- Some car stereos show "Phone" or "Call" on screen, or mute the radio, while HFP is active. Explain this in onboarding: "Your car may show a call screen, that's normal."
- A real incoming phone call takes priority. Pause the quiz on `AVAudioSession.interruptionNotification`, then say "Welcome back! Let's keep going" afterwards.
- Handle route changes (`routeChangeNotification`), such as the car turning off or Bluetooth dropping out. Switch to the phone's speaker and mic, or pause, as set in Settings.
- Setting: **"Microphone source"**, with options Auto (prefer the car), iPhone, or Headset.
- Setting: **"Mic check"**. The app says "Say 'hello'", then shows a level meter and confirms "I can hear you!"

### 2.5 Settings
- Voice (choose from available `en-AU`, `en-GB` and `en-US` voices) and speech rate.
- Think time.
- Toggle for reading the multiple-choice options aloud.
- Fun facts on/off.
- Background music/ducking behaviour.

---

## 3. Paid Tier ("Family Pass")

### 3.1 Players
- Create up to 6 player profiles, each with a **name**, **age band** and **avatar/colour**. Up to 6 can play together with the Family Pass (2 for free).
- A **live scoreboard** sits at the top of the screen during every question, for every player, from the first question. Scores are kept per game and added to each player's lifetime points. **Settings → Scoreboard** turns it off (on by default): no scores on screen or read out, but points still count towards badges.
- **Fixing scores:** after the scores are read out, the app says "If we missed anyone's answer, a grown-up can fix the scores with the edit button." Each row on the final scoreboard has a pencil: − / + in steps of 10, between 0 and the most that player could have scored, then Save. The change is saved to their lifetime points.
- While listening, the **microphone and the countdown show side by side**, so it's clear the app is still listening while the clock runs. If listening isn't running, a small note says answers are being read out.
- **Background play** (Settings → Audio) is a choice. The first time a game goes to the background it keeps playing (so a car trip isn't interrupted), and the parent is asked "Keep playing in the background?" when they're back in the app. The answer is remembered. Off: the game pauses until they return.
- Before a session, pick who's playing.

### 3.2 Turn-based play
- The app rotates through players: "**Mia**, this one's for you: what's the capital of Tasmania?"
- Each player gets questions from their **own age band**, even within the same topic.
- **No speaker identification:** whoever's turn it is gets the score.
- Optional "Open round" mode: the first correct answer from anyone wins. The parent then says or taps the name of the player who answered. This can be a later feature (v1.1).

### 3.3 Voice answers
After the question is read:
1. Play an "I'm listening" chime.
2. Listen for up to the think time.
3. Pass what was heard to the answer matcher (3.4).
4. Respond out loud with "Correct!" plus a random cheer. Otherwise just share the answer
   ("The answer is… X!"), with no "Not quite" or ✗.
- If nothing (or only a mumble) is heard, say nothing about it: share the answer and move on.
  No retry, no score, no change to the Leitner boxes (ADR-0018, "Joy, not correction").
- Voice commands during the game: "skip", "repeat", "pause", "stop", "next".
- **Skip or Next before the answer keeps the turn with the same player** (on screen, car
  button or voice): they get another question ("Here's another one."), and the skip doesn't use
  up one of the game's questions. After the answer, Next moves on to the next player.

### 3.4 Answer matching (in `QuizEngine`, unit-tested)
- Normalise both sides: lowercase, strip punctuation, ignore "the/a/an", trim.
- Accept any entry in the question's `acceptedAnswers` list.
- Number handling: "seven" equals "7", and "twenty one" equals "21".
- Fuzzy match using Levenshtein distance, with a threshold scaled to answer length, for example ≤1 for short words and ≤2 for words longer than 6 letters.
- Multiple choice: accept the option letter ("B"), the option text, or "option B".
- Keep all of the speech recognizer's alternative transcriptions and accept a match from any of them.

### 3.5 Scoring
- +10 points for a correct answer, with a streak bonus of +5 for each correct answer after the first two in a row.
- An end-of-session scoreboard is read aloud: "Mia wins with 80 points! Leo got 60!"
- Per-player stats: total correct, best streak and accuracy per topic.
- Simple badges, for example "10 in a row" or "Space Expert" for 80% or more in Space.

### 3.6 Unlocks
- All topics.
- Endless mode.
- Custom session mix (several topics shuffled together).

### 3.7 Pricing (StoreKit 2)
- **Family Pass (lifetime):** A$9.99 non-consumable.
- **Optional subscription:** A$3.99/month or A$24.99/year. The subscription can be added later. v1 can ship with the lifetime purchase only.
- **Restore Purchases** button (required by Apple).
- Family Sharing enabled.

---

## 4. Content

### 4.1 Question JSON schema
```json
{
  "id": "geo-0001",
  "topic": "geography",
  "ageBand": "6-8",
  "type": "open",
  "question": "What is the capital city of Tasmania?",
  "options": null,
  "answer": "Hobart",
  "acceptedAnswers": ["hobart", "hobart city"],
  "funFact": "Hobart is Australia's second-oldest capital city.",
  "difficulty": 2,
  "minAge": null,
  "region": "AU"
}
```
- `type`: `multipleChoice` (3 options) | `trueFalse` | `talkAbout`. *(ADR-0015 removed `open` and merged `scenario` into `multipleChoice`.)*
  - `scenario`: a short social situation with 3 spoken options. Scored like multiple choice.
  - `talkAbout`: an open discussion prompt with **no scoring** and no right answer (see 4.3).
- Optional field `explanation`: one kind sentence explaining *why* the answer is the good choice. It's read aloud after the answer in place of `funFact`.
- `options`: an array of 3–4 strings when `type = multipleChoice`.

### 4.2 Content requirements
- Launch target: **8 topics × 3 age bands × at least 60 questions** (about 1,500 questions).
- Questions must be short enough to read aloud in **≤12 seconds**.
- Answers must be **easy to say aloud**: avoid long or ambiguous answers, and prefer one or two words.
- Lean toward Australian content: places, animals and history.
- Add a content validation script (Swift or Python, run in CI) that checks the schema, finds duplicate IDs and missing `acceptedAnswers`, and estimates speaking length.

### 4.3 Manners & Friendship topic
Teaches kindness, manners, friendship and feelings through everyday situations.

**Sub-themes:** saying please, thank you and sorry; sharing and taking turns; including others; handling feelings (angry, sad, left out); being a good winner and loser; table and car manners; online kindness (11–12 only); asking for help.

**Question styles**
- **Scenario (scored):** "Your friend falls over at the park. What's the kind thing to do? A: laugh, B: help them up and ask if they're okay, C: keep playing." Then the answer, plus the `explanation`: "Helping shows you care, and they'd do the same for you."
- **True/false (scored):** "It's okay to feel angry, as long as we don't hurt anyone. True or false?"
- **Talk About (not scored):** "What's something kind someone did for you this week?" Parent mode's own timer (default 30 seconds, or no limit): the app says "Take your time and talk it over" and waits until the timer ends or someone presses Next (on screen or the car's next-track button), then says "Great chat!" and moves on. In the paid tier, it's addressed to the player whose turn it is but **awards no points**.

**Content rules**
- Positive framing: reward the kind choice and never shame a wrong answer. A wrong answer gets "Good try! A kinder choice might be…", never "Wrong!"
- Wrong options should be plausible kid behaviour, not silly or cruel.
- No sensitive topics: no bullying details, body safety, family conflict or religion. Those belong with parents and schools. (Personal and online safety are covered separately in 4.6.)
- Talk About prompts must stay light and never ask kids to share private or family information.
- In voice mode, add a **"Parent mode" toggle** that skips Talk About prompts when the app is used alone.
- Launch target for this topic: at least 40 scenario/true-false questions and 20 Talk About prompts per age band.
- Content should be reviewed by a parent or teacher before release.

### 4.4 Question selection
- Don't repeat questions within a session.
- ~~Track questions already seen per player and prefer unseen ones until the pool runs out.~~ Replaced by per-player Leitner boxes ([ADR-0016](adr/0016-leitner-spaced-repetition.md)): due reviews first, then new questions. A player gets a question at most once per session.
- Shuffle the order of multiple-choice options.

### 4.5 Values & Life Skills topics
These use the same question types as 4.3 (scenario, true/false, Talk About) and the same content rules.

| Topic | 6–8 | 9–10 | 11–12 | Notes |
|---|---|---|---|---|
| **Manners & Friendship** | ✅ | ✅ | ✅ | See 4.3 |
| **Respect & Differences** | ✅ | ✅ | ✅ | Cultures, languages, festivals, food, abilities and disabilities, looks. Explicit "treating people fairly whatever their skin colour or background" from 9+. |
| **Feelings** | ✅ | ✅ | ✅ | Naming emotions, calming down, noticing how others feel |
| **Honesty & Fairness** | ✅ | ✅ | ✅ | Telling the truth, owning up, playing fair |
| **Never Give Up** (growth mindset) | ✅ | ✅ | ✅ | Mistakes help us learn, trying again, asking for help |
| **Staying Safe** | ✅ | ✅ | ✅ | Road, water, sun ("Slip, Slop, Slap"), fire, calling 000 |
| **Caring for Our Planet** | ✅ | ✅ | ✅ | Recycling, saving water, native wildlife |
| **Kindness to Animals** | ✅ | ✅ | — | Pet care, respecting wildlife |
| **Healthy Habits** | ✅ | ✅ | ✅ | Sleep, teeth, handwashing, being active. No weight, dieting or "good/bad food" talk. |
| **Teamwork & Leadership** | — | ✅ | ✅ | Listening, sharing jobs, being a good captain |
| **Being an Upstander** | — | ✅ | ✅ | Gentle "what could you do if someone's left out or teased?", always including telling a trusted adult |
| **Money Smarts** | — | ✅ | ✅ | Needs vs wants, saving, earning |
| **Online Safety & Scams** | ✅ | ✅ | ✅ | See 4.6 |
| **Personal Safety & Security** | ✅ | ✅ | ✅ | See 4.6 |
| **First Nations Cultures** | ✅ | ✅ | ✅ | Part of the Australian Curriculum. **Must be written or reviewed with Aboriginal and Torres Strait Islander input before release.** |

**How questions change by age band**
- **6–8:** simple true/false or 2–3 short options, everyday home and school situations, very short sentences.
- **9–10:** 3-option scenarios with a bit more nuance (for example "your friend asks you to keep a secret that worries you"), plus "why" explanations.
- **11–12:** trickier situations (group chats, peer pressure, fairness), more Talk About prompts, and "what would you do?" answers that can have more than one good choice.
- **Optional 4–5 band (later):** voice-only works for kids who can't read yet. Simple true/false only ("Is it kind to share your toys? True or false?").

**Extra content rules for values topics**
- Celebrate differences. Never state a stereotype, even as a wrong option to reject.
- No slurs or hurtful words, even quoted.
- Stay away from politics, religion and current events.
- Every unsafe scenario ends with "tell a trusted adult".
- Each question has an `ageBand`. Values topics may also set `minAge` when a question only fits the top of a band.

### 4.6 Safety & Security topics

**Online Safety & Scams**
- **6–8:**
  - Never share your password, except with mum or dad.
  - Ask a grown-up before clicking, downloading or buying anything.
  - Not everyone online is who they say they are.
  - If something online feels yucky or scary, tell an adult.
- **9–10:**
  - Fake prizes ("You won a free iPad!").
  - Scams offering free game currency (V-Bucks, Robux).
  - Strong passwords.
  - Keep personal info private: full name, school, address, photos in uniform.
  - Don't open strange links or messages.
  - In-app purchases cost real money.
- **11–12:**
  - Phishing: spotting fake emails, texts and websites.
  - Account hacking, and why you should never share login codes.
  - Fake profiles.
  - Online friends you haven't met in real life.
  - Screenshots last forever, and think before you post.
  - Cyberbullying: don't reply, keep evidence (screenshots), block, report, tell an adult.
  - Using a device's privacy settings.
- **Warning signs (9+), kept general:** someone online asks you to keep secrets, asks for photos, offers gifts, or asks to move to a private chat. The answer is always: stop, don't reply, and tell a trusted adult.

**Personal Safety & Security**
- **6–8:**
  - Know your full name, your address and a parent's phone number.
  - Call 000 in an emergency.
  - Who your safe adults are.
  - What to do if you get lost (stay put, find a worker or a parent with kids).
  - Don't go anywhere with someone without checking with your grown-up first.
- **9–10:**
  - Don't open the door to people you don't know.
  - Have a family "safe word".
  - Trust your "uh-oh" feeling.
  - Walking or riding safely to school.
- **11–12:**
  - Phone safety (location sharing, unknown callers).
  - Saying no to peer pressure.
  - Who to ask for help: police, school staff, Kids Helpline.
  - Telling the difference between a secret and a surprise.

**Content rules**
- Tone is calm and empowering, never scary. Use "safe adults" framing rather than "stranger danger".
- Every scenario ends with a clear action: **stop, block, tell a trusted adult**.
- Never describe crimes or offender tactics in detail. Keep warning signs general.
- Base content on the **eSafety Commissioner** (esafety.gov.au) and **ThinkUKnow Australia** guidance. A parent or teacher must review it before release.
- Talk About prompts for this topic include "Who are your safe adults?" and "What would you do if a game asked for your password?" These suit Parent mode.

---

## 5. Kids Category & Privacy Compliance

- **Parental gate** before any purchase, settings change, external link or support email. For example, a simple adult maths question or a press-and-hold.
- No third-party analytics, ads or tracking SDKs.
- Microphone and speech-recognition permission prompts with clear wording, for example: "Used to hear your child's answers. Audio is processed on this device and never stored or sent anywhere."
- Never store or record audio.
- Privacy policy page (static, hosted for free) and App Privacy label: **Data Not Linked to You: Diagnostics** (anonymous error reports, ADR-0020).

---

## 6. Onboarding

1. Welcome screen: "Welcome to BuckleUp Quiz, the screen-free quiz for car trips."
2. Ask for microphone permission, only when a paid voice feature is first used, or during onboarding if a free trial is offered.
3. Quick 3-question demo in Listen mode.
4. Optional: create the first player.

---

## 7. Out of Scope for v1

- CarPlay app UI (planned for v1.1, after applying for Apple's voice-based conversational app entitlement).
- Android.
- Online multiplayer, accounts and a backend.
- AI-generated questions in real time.
- Identifying who's speaking by their voice.
- Parent progress emails or a dashboard.
- Custom question packs written by parents.

---

## 8. Suggested Build Milestones

1. **M1 – Engine:** JSON loader, `QuizEngine` (selection, scoring, answer matching) and unit tests.
2. **M2 – Listen mode:** TTS, think timer, answer reveal, background audio, remote controls, lock screen.
3. **M3 – UI:** home/topic grid, age band picker, quiz screen, settings.
4. **M4 – Voice answers:** speech recognition, the listening state machine, retry, voice commands, **car Bluetooth microphone (HFP)**, echo cancellation and route-change handling.
5. **M5 – Players & scoring:** profiles, turn rotation, scoreboard, badges.
6. **M6 – Paywall:** StoreKit 2, locked topics, restore, parental gate.
7. **M7 – Content & polish:** full question bank, validation script, sounds, app icon, App Store screenshots.
8. **M8 – TestFlight:** test in a real car with road noise and kids.

---

## 9. Acceptance Criteria (key)

- [ ] A full 20-question Listen-mode session runs with the **screen locked**, through car Bluetooth, with no taps.
- [ ] A phone call interruption pauses the quiz and resumes it cleanly afterwards.
- [ ] In voice mode, connected to a car over Bluetooth, the app speaks through the car speakers **and** hears answers through the car microphone, with no taps. Test on at least 3 different car stereos, plus CarPlay.
- [ ] Echo test: the app never marks its own spoken options or answer as a player's answer.
- [ ] If Bluetooth disconnects mid-question, the app falls back to the phone's mic and speaker, or pauses, without crashing.
- [ ] Voice answers are matched correctly at least 90% of the time in a quiet room and at least 75% with simulated road noise (test set of 100 spoken answers).
- [ ] Number words, articles and small mispronunciations are accepted (unit tests).
- [ ] Turn rotation gives each player questions from their own age band.
- [ ] Purchases, restore and the parental gate work in the StoreKit sandbox.
- [ ] No network requests are made at runtime (verify with a proxy).

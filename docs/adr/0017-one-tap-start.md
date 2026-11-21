# 0017. One tap to play: remembered setup, random or chosen topic

- **Status:** Accepted
- **Date:** 2026-11-22
- **Amends:** FEATURES §2.1, §6; [ADR-0015](0015-choice-questions-and-named-players.md) (session setup flow)

## Context
Starting a game took several steps: topic → who's playing → length → Start. In a car, that's
too slow. The product decision is to make it **frictionless**. After the first game, nobody
should have to pick players again unless they want to change them. Opening the app and
pressing one button should start a game.

## Decision
- **Who's playing and the length are remembered** (`AppSettings.selectedPlayerIDs`,
  `lastSessionLength`). Home shows them at the top ("Mia and Leo · 10 questions") with a
  **Change** button that opens *Game setup* (players, length, Edit players).
- **Play** (the big button) starts at once on a **random topic**: an unlocked one where every
  selected player has something to play today, otherwise one where at least one does.
- **Tapping a topic** starts that topic at once.
- **Only before the first game** (nobody selected yet) does Play or a topic open Game setup
  first; its "Let's go!" button starts the game as soon as the sheet closes.
- A lone player is pre-selected; removed players drop out of the selection.
- If nobody has anything left (see ADR-0016), Home says so instead of starting an empty game.
- The old per-topic setup screen (`SessionSetupView`) is removed.

## Alternatives considered
- **Keep the setup screen but pre-fill it.** It still costs a tap per game and a screen to
  read; the user asked for no setup when it's already set.
- **Auto-start on launch.** Too surprising, since the app might open while parked or with
  the wrong people in the car. One deliberate tap is enough.

## Consequences
- Two taps from opening the app to the first question: open, then Play.
- Changing players is one tap away (Change), but it's never forced.
- Mixed-topic sessions (paid) can later slot into "Play" without changing the flow.

# 0008. Audio: one session mode per session, half-duplex, cue engine

- **Status:** Accepted
- **Date:** 2026-11-22

## Context
FEATURES §2.3–2.4: hands-free play through car Bluetooth or CarPlay, with the screen locked.
Voice mode uses the car microphone through Bluetooth HFP. Switching between HFP and A2DP
mid-session causes 1–3 second gaps on many car stereos.

## Decision
- **One `AVAudioSession` configuration per session, chosen at start and never switched:**
  - Listen mode (free): `.playback`, mode `.spokenAudio`, output over **A2DP**. Options
    `.duckOthers` + `.interruptSpokenAudioAndMixWithOthers` when "lower music" is on.
  - Voice mode (M4): *(superseded in part by [ADR-0018](0018-hands-free-voice-answers.md): mode
    `.default`, not `.voiceChat`)* `.playAndRecord`, mode `.voiceChat`, with
    `[.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker, .duckOthers]`. The Bluetooth HFP
    input is picked explicitly with `setPreferredInput`. Voice processing on the input node
    gives echo cancellation.
- **Half-duplex turn-taking:** never listen while speaking. The order is: speak → 300 ms →
  listening chime → open the mic.
- **TTS:** `AVSpeechSynthesizer` on the app's audio session, defaulting to an `en-AU` voice at a
  slightly slow rate. It's wrapped as `SpeechOutput.speak() async throws`, so cancelling
  (pause or skip) stops speech immediately.
- **Cue engine:** an `AVAudioEngine` player node plays generated sounds (think tick, listening
  chime) and loops near-silence in between. With the screen locked, iOS suspends background-audio
  apps that stop producing audio. Without this, the app would be suspended during the silent
  think time. The engine only runs while a session is active.
- **Interruptions** (phone calls, Siri, navigation prompts) pause the quiz. When the
  interruption ends, the app says "Welcome back! Let's keep going." and re-reads the current
  question. **Losing the output device** (car off, Bluetooth drops) pauses.
- **Remote commands:** play/pause/toggle, next (skip) and previous (repeat) work from
  headphones, the lock screen and steering-wheel buttons. Now Playing shows the topic and
  question number.

## Consequences
- Some car stereos show a "call" screen during HFP. Onboarding will explain this (M4).
- The near-silent loop must stop when a session ends, or App Review may flag background audio
  abuse. `ListenSessionModel.tearDown()` always calls `endSession()`.
- Real-car testing on at least 3 head units plus CarPlay is an M8 exit criterion.

# VoiceMiddle

Real-time bidirectional voice translation for macOS, designed to work with any
communication app (Microsoft Teams, Google Meet, Slack, Zoom, Discord, …)
without per-app integration.

VoiceMiddle sits in the middle of the audio path: it captures the audio your
communication app plays and the audio your microphone produces, translates each
direction in real time, and exposes the result back to the system. The other
party hears your voice translated into their language through their normal call
audio; you hear their voice translated into yours (optionally; you can also
just read a live transcript).

## How it works (in one paragraph)

VoiceMiddle uses **Core Audio Process Taps** (macOS 14.6+) to capture the
output audio of a target communication app, runs it through **ElevenLabs Scribe
v2 (realtime STT)** → a pluggable translator (**Claude**, **GPT**, or **DeepL**)
→ **ElevenLabs Flash/Turbo v2.5 (streaming TTS)**, and either plays the
translated audio in your headphones, displays a transcript, or both. In the
opposite direction, your microphone audio runs through the same pipeline and
the translated audio is written into a system-wide virtual microphone provided
by a bundled DriverKit System Extension. The communication app selects that
virtual microphone as its input device, so the other party hears your
translated voice as if it were your normal microphone.

## Status

Pre-implementation. The design document lives at
[`docs/design.md`](docs/design.md). All code and documentation in this
repository are written in English.

## Requirements

* macOS 14.6 (Sonoma) or later. The bundled driver targets DriverKit 23.6.
* ElevenLabs API key (for Scribe v2 realtime STT and Flash/Turbo v2.5 TTS).
* One of: Anthropic API key, OpenAI API key, or DeepL API key, for the
  translation step.

## Key features

* **Bidirectional translation with mic injection.** The other party does not
  need to install anything.
* **Communication-app agnostic.** Works with any macOS app that plays audio and
  uses a microphone.
* **Configurable translator.** Pick Claude, GPT, or DeepL per session.
* **Configurable pacing.** Turn-based (uses voice activity detection, highest
  quality) or streaming (lower latency, may self-correct).
* **Read-only inbound mode.** Suppress TTS on the inbound direction and just
  read a live transcript when you'd rather not have synthesized voice in your
  ears.
* **Ducking of original audio.** The original speaker's audio is automatically
  ducked while the translation plays, with configurable level (default
  −20 dB) or full muting.

## Repository layout (target)

```
voice-in-the-middle/
├── README.md
├── docs/
│   └── design.md                 ← full design spec
├── VoiceMiddle/                  ← SwiftUI macOS app (Xcode project)
│   ├── App/                      ← app lifecycle, menu bar, settings UI
│   ├── Audio/                    ← Core Audio Taps, AVAudioEngine, routing
│   ├── Pipeline/                 ← STT → Translator → TTS orchestration
│   ├── Translators/              ← Claude, GPT, DeepL implementations
│   ├── Services/                 ← ElevenLabs Scribe + Flash clients
│   └── Settings/                 ← persisted settings, Keychain
└── VoiceMiddleDriver/            ← DriverKit System Extension (virtual mic)
```

## Permissions

VoiceMiddle requires the following macOS permissions (the app requests them on
first launch):

| Permission | Why |
|---|---|
| Microphone | Capture the user's voice for translation. |
| Audio capture (Core Audio Process Tap) | Capture the target app's output audio. |
| System Extension installation | Install the virtual microphone driver. |
| Accessibility (optional) | Global hotkey to toggle a session. |
| Network | Reach ElevenLabs and the translator API. |

## Outbound translation (you → other party)

VoiceMiddle's outbound side (translating your voice so the other party hears
their language) routes audio through a virtual microphone. Two options:

1. **BlackHole (recommended for now):** install once via Homebrew.

   ```
   brew install --cask blackhole-2ch
   ```

   Approve the System Extension prompt in System Settings → Privacy &
   Security. In VoiceMiddle Settings → Audio, enable "Translate my voice to
   the other party" and leave the device name as `BlackHole 2ch`. In your
   communication app (Teams/Meet/Slack), select `BlackHole 2ch` as the
   microphone input.

2. **VoiceMiddleDriver (planned):** a bundled DriverKit System Extension. Not
   yet usable because it requires Apple-approved DriverKit entitlements. Once
   approved, the device appears as `VoiceMiddle Mic` system-wide.

## License and credits

To be defined.

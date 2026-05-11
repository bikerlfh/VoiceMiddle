# VoiceMiddle — Design Specification

**Status:** Draft for review
**Date:** 2026-05-11
**Target platform:** macOS 14.6 (Sonoma) or later, aligned with DriverKit 23.6
for the bundled System Extension. Windows / Linux are explicit
future goals but out of scope for the MVP.

---

## 1. Goals and non-goals

### 1.1 Goals

1. **Real-time bidirectional translation between two languages** during a live
   voice or video call.
2. **Communication-app agnostic.** Works with any macOS app that plays audio
   and uses a microphone (Microsoft Teams, Google Meet, Slack, Zoom, Discord,
   FaceTime, …) with no per-app code.
3. **Bidirectional with injection.** The other party does not need to install
   anything: they hear the user's translated voice through their normal call
   audio because the user's translated voice is exposed as a system virtual
   microphone.
4. **Latency budget:** ~1.5–3 seconds end-to-end in turn-based mode, ~700 ms–1
   second in streaming mode (measured from end of source utterance to start of
   translated audio playback).
5. **Configurable translation engine:** the user can choose between Claude
   (Anthropic SDK), GPT (OpenAI SDK), and DeepL at runtime per session.
6. **Read-only inbound mode:** the user can disable TTS on the inbound
   direction and read the transcript instead, while the outbound direction
   (their own voice → other party) continues to synthesize speech.
7. **Configurable ducking** of the original audio while the translation plays
   (default −20 dB; also full mute or no ducking).

### 1.2 Non-goals (MVP)

* Group calls with more than two participants.
* Languages other than the one configured language pair per session
  (changing the pair requires reconfiguring).
* Voice cloning of the speakers. (Planned for a later phase; the architecture
  is designed to accept it as a drop-in voice provider, but the MVP ships with
  preset ElevenLabs voices.)
* Translation of system notifications, music, or other non-call audio.
* Windows or Linux ports.

---

## 2. High-level architecture

VoiceMiddle is composed of two binaries:

1. **`VoiceMiddle.app`** — the user-facing SwiftUI macOS application. Hosts
   the UI, the translation pipelines, and the audio capture/routing logic.
2. **`VoiceMiddleDriver`** — a DriverKit System Extension built with
   AudioDriverKit. It registers a single virtual input audio device named
   "VoiceMiddle Mic" that is visible system-wide. Communication apps select
   it as their input device, and the main app writes translated outbound
   audio into it.

```
                    ┌─────────────────────────────────────┐
                    │   Communication app (Teams/Meet/…)  │
                    └─────────┬────────────────────▲──────┘
                              │ output             │ input
                              │ (other party       │ (selects
                              │  speaking)         │  VoiceMiddle Mic)
                              ▼                    │
   ┌──────────────────────────────────────────────────────┐
   │                     VoiceMiddle.app                  │
   │                                                      │
   │  ┌────────────────┐        ┌────────────────┐        │
   │  │ App audio tap  │        │ Mic capture    │        │
   │  │ (Core Audio    │        │ (AVAudioEngine │        │
   │  │  Process Taps) │        │  input node)   │        │
   │  └───────┬────────┘        └───────┬────────┘        │
   │          ▼                         ▼                 │
   │  ┌────────────────┐        ┌────────────────┐        │
   │  │ Pipeline A→B   │        │ Pipeline B→A   │        │
   │  │ other → me     │        │ me → other     │        │
   │  │ (e.g. EN → ES) │        │ (e.g. ES → EN) │        │
   │  └───────┬────────┘        └───────┬────────┘        │
   │          ▼                         ▼                 │
   │  ┌────────────────┐        ┌────────────────┐        │
   │  │ Playback to    │        │ Write into     │        │
   │  │ headphones +   │        │ VoiceMiddle    │        │
   │  │ HUD transcript │        │ Mic (driver)   │        │
   │  └────────────────┘        └────────────────┘        │
   └──────────────────────────────────────────────────────┘
                              ▲
                              │ XPC / shared ring buffer
                              ▼
            ┌───────────────────────────────────────────┐
            │  VoiceMiddleDriver (AudioDriverKit ext.)  │
            │  Provides system-wide virtual input       │
            │  device "VoiceMiddle Mic".                │
            └───────────────────────────────────────────┘
```

Each direction runs as an independent Swift `actor`. The two directions are
fully concurrent: the user can speak and the other party can speak overlapping
in time, and both pipelines process audio independently.

---

## 3. Audio capture and routing

### 3.1 Capturing audio from the target communication app

* **API:** Core Audio Process Taps (`CATapDescription`,
  `AudioHardwareCreateProcessTap`, `AudioHardwareCreateAggregateDevice`).
  Available since macOS 14.4; we require 14.6 to match DriverKit 23.6.
* **Mode:** per-process tap targeting the PID of the selected communication
  app. We use a single tap; if the user switches the target app at runtime,
  the existing tap is destroyed and a new one is created.
* **Format:** the tap is configured with a 48 kHz / mono / Float32 stream
  format (resample on the fly inside the tap thread). Mono is enough; Scribe
  receives mono.
* **Delivery:** the tap's I/O proc writes PCM frames into a lock-free ring
  buffer that the `AppAudioCapture` actor drains.
* **Process discovery:** at startup and on demand, enumerate processes with
  active audio output (`kAudioHardwarePropertyProcessObjectList`) and filter
  to a curated list of known communication apps; the user can also pick any
  process by name.

### 3.2 Capturing the user's microphone

* `AVAudioEngine` with the input node configured to deliver 48 kHz / mono
  Float32 buffers. The selected microphone is the system default input unless
  the user picks a specific device in settings.
* The engine also installs a tap on the input node to feed the Pipeline B→A
  voice activity detector and the Scribe stream client.

### 3.3 Playing the inbound translation

* Output goes to the **system default output device** (the user's headphones)
  via a dedicated `AVAudioPlayerNode` attached to a shared `AVAudioEngine`.
* The output engine is also responsible for the **ducking** of the original
  call audio. The original audio is not muted at the source — instead, an
  `AVAudioMixerNode` mixes:
  * The original tap audio (so the user can keep some sense of the speaker's
    cadence and emotion), routed through a smoothed gain stage that the
    pipeline controls.
  * The translated TTS audio from the Pipeline A→B sink.
* When TTS is about to play, the pipeline ramps the original-audio gain from
  0 dB to the configured ducking level (default −20 dB) over 80 ms, holds
  it, and ramps back when TTS finishes. The ramp avoids audible clicks.
* Three ducking modes are configurable in Settings:
  * **Off:** original audio plays at full level alongside the translation.
  * **Duck to level (default):** original audio is attenuated by the
    configured amount (default −20 dB, range −40 dB to 0 dB).
  * **Mute:** original audio is silenced while the translation plays.

### 3.4 Injecting the outbound translation as a virtual microphone

* The **VoiceMiddleDriver** System Extension implements an
  `IOUserAudioDevice` subclass that exposes a single input stream (the
  virtual microphone). The driver maintains an in-process ring buffer and
  serves audio frames to whatever app has opened the device.
* The main app communicates with the driver through an XPC channel
  (preferred) or a shared memory region published by the driver. We will
  start with the AudioDriverKit-recommended XPC pattern: the app pushes
  Float32 frames at the device sample rate, and the driver writes them into
  its ring buffer.
* When Pipeline B→A produces TTS audio, it is written into the driver. If no
  TTS audio is available, the driver writes silence so the consuming app
  always sees a continuous stream.
* **Open question to resolve in implementation:** whether to also surface the
  user's own (untranslated) voice on a second virtual device, for cases
  where the user wants to keep their original audio available to record
  locally. Initially not exposed.

### 3.5 Voice activity detection

* Each pipeline has its own VAD. We use a small energy-and-zero-crossing VAD
  in MVP (cheap, no model load) with hangover of 600 ms. The threshold is
  per-direction configurable in Settings → Audio.
* Future improvement: swap for an on-device Silero-style VAD via CoreML.

---

## 4. Translation pipeline

Two independent pipelines run in parallel, one per direction. They share only a
`ConversationContextActor` instance (see §4.3).

### 4.1 Pipeline stages

```
AudioSource → Chunker(VAD) → ScribeStreamClient
                                     │
                                     ▼ (partial + final transcripts)
                              TranscriptAggregator
                                     │
                                     ▼ (utterance text)
                                Translator
                                     │
                                     ▼ (translated text)
                            ┌────────┴────────┐
                            ▼                 ▼
                       TTSStream         TranscriptUI
                       (Flash v2.5)
                            │
                            ▼
                       AudioSink
                       (headphones | virtual mic)
```

The same pipeline class is used in both directions; only the source, sink, and
language configuration differ.

### 4.2 Pace modes

Each direction is independently configurable between:

* **Turn-based (default for inbound, recommended for interviews):**
  * The `Chunker` accumulates PCM frames until the VAD reports `silence >
    600 ms` (configurable). At that point, it calls `endStream()` on the
    Scribe client and waits for the final transcript.
  * The full utterance is sent to the `Translator`, the translation is
    streamed to Flash TTS, and the audio is played.
  * **Pros:** highest quality, no self-correction artifacts, full
    conversation context available to the translator.
  * **Cons:** the listener hears nothing during the translation gap (~1.5–3 s).

* **Streaming:**
  * The `TranscriptAggregator` emits a `flushable` event at every clause
    boundary (comma, semicolon, "and"/"but"/"so" at start of a phrase, or
    every 1.2 s of accumulated text, whichever comes first). At each flush,
    a partial translation request is dispatched.
  * Translated fragments are queued into Flash as they arrive. Flash itself
    streams audio chunks back at low latency.
  * **Pros:** ~700 ms–1 s perceived latency, more conversational feel.
  * **Cons:** translator sees less context per call, fragments may be
    grammatically awkward, occasional self-correction artifacts where the
    next fragment starts in a way that doesn't perfectly continue the
    previous one.

The mode is observable as a `@Published` property on each pipeline; switching
it does not require restarting the session.

### 4.3 Conversation context

For translators that support it (Claude, GPT), each translation call includes
the last N (default 6) utterance pairs from *both* directions:

```swift
struct ConversationContext {
    struct Turn {
        let direction: Direction          // .inbound or .outbound
        let original: String
        let translated: String
        let timestamp: Date
    }
    let recentTurns: [Turn]                // newest last; capped at N
    let sessionTopicHint: String?          // optional user-provided hint
}
```

`ConversationContextActor` is the single source of truth, accessed via
`actor`-isolated methods from both pipelines. After each successful
translation, the pipeline calls `await contextActor.appendTurn(...)`.

DeepL ignores `ConversationContext` (its API doesn't accept conversation
context).

### 4.4 Interfaces (Swift)

```swift
/// A pluggable text translator.
///
/// Implementations must be thread-safe. They will be called concurrently from
/// the two pipelines.
protocol Translator: Sendable {
    /// Identifies the translator (e.g. ``.claudeHaiku45``, ``.gpt4oMini``,
    /// ``.deepL``). Used by Settings and by ``ConversationContextActor``
    /// to skip the context payload when not supported.
    var identifier: TranslatorID { get }

    /// Whether this translator can make use of ``ConversationContext``.
    var supportsContext: Bool { get }

    /// Translates ``text`` from ``source`` to ``target``.
    ///
    /// - Parameters:
    ///   - text: The source utterance.
    ///   - source: BCP-47 language code, e.g. ``"en"``.
    ///   - target: BCP-47 language code, e.g. ``"es"``.
    ///   - context: Recent turns from both directions, or ``nil`` if the
    ///     translator does not support context.
    /// - Returns: The translated text.
    /// - Throws: ``TranslationError`` for upstream failures.
    func translate(
        _ text: String,
        from source: LanguageCode,
        to target: LanguageCode,
        context: ConversationContext?
    ) async throws -> String
}

/// Realtime speech-to-text stream client.
///
/// Implementations open a persistent WebSocket. The caller pushes PCM frames
/// in real time; partial and final transcripts flow back asynchronously.
protocol STTStreamClient: Sendable {
    /// Partial transcripts emitted as the user speaks. Each value is the
    /// most recent best guess (not a delta).
    var partials: AsyncStream<String> { get }

    /// Final transcripts emitted after the upstream confirms an utterance.
    var finals: AsyncStream<String> { get }

    /// Pushes 48 kHz / mono / Float32 frames to the upstream.
    func send(_ pcm: AVAudioPCMBuffer) async

    /// Signals the end of an utterance so the upstream emits the final
    /// transcript.
    func flushUtterance() async

    /// Closes the underlying transport.
    func close() async
}

/// Streaming text-to-speech client.
///
/// Implementations stream synthesized audio chunks back via the provided
/// sink. The sink is called from a high-priority audio thread; do not block
/// in the sink.
protocol TTSStreamClient: Sendable {
    /// Synthesizes ``text`` using ``voice``. Calls ``sink`` for each chunk
    /// of Float32 PCM at 48 kHz / mono until synthesis completes.
    func synthesize(
        _ text: String,
        voice: VoiceID,
        sink: @Sendable (Data) -> Void
    ) async throws
}
```

### 4.5 Translator implementations

| Implementation | Transport | Default model | Notes |
|---|---|---|---|
| `ClaudeTranslator` | Anthropic REST API (Messages) over `URLSession` | `claude-haiku-4-5-20251001` | Default. Sends `ConversationContext` as a structured user message, uses prompt caching for the static system prompt. |
| `GPTTranslator` | OpenAI REST API (Chat Completions) over `URLSession` | `gpt-4o-mini` (configurable) | Sends `ConversationContext` as a `messages[]` history. |
| `DeepLTranslator` | DeepL REST API over `URLSession` | n/a | Fastest; no context. Recommended for streaming pace mode. |

There is no first-party Anthropic or OpenAI SDK for Swift. Each translator
wraps `URLSession` directly with a small typed request/response layer. We
may later adopt a community SDK if one becomes stable enough, but the
abstraction lives behind the `Translator` protocol either way.

Each translator has its own settings panel that exposes its model selector
(when applicable), endpoint override (for self-hosted setups), and API key
field (stored in Keychain).

### 4.6 STT / TTS implementations

* **`ScribeV2StreamClient`** — connects to ElevenLabs Scribe v2 realtime
  WebSocket endpoint. Sends Float32 PCM frames at 48 kHz mono, receives
  partial and final transcripts. Reconnects with exponential backoff on
  transport failure.
* **`FlashV2StreamClient`** — connects to ElevenLabs Flash v2.5 (Eleven Flash)
  WebSocket endpoint with `optimize_streaming_latency` set. Receives PCM
  chunks and forwards them to the sink. We use Flash by default and expose
  Turbo as an alternative in Settings → Translation → TTS.

### 4.7 Error handling

| Failure | Behaviour |
|---|---|
| Scribe WebSocket drops | Buffer up to 1 second of mic audio while reconnecting with exponential backoff (250 ms → 4 s). Drop older audio rather than replay it; the call has moved on. Surface a small red dot on the HUD. |
| Translator call fails | Show the source transcript only; do not synthesize TTS in the wrong language. Log error, retry once with jitter, then surface error to HUD. |
| Flash WebSocket drops | Transcript continues to render. Reconnect with exponential backoff. TTS for the current utterance is dropped. |
| Audio device disappears (headphones unplugged) | Pause the inbound pipeline, surface a notification, and resume on the new default output. |
| VoiceMiddle Mic driver crashes | The communication app sees silence on the virtual mic until the driver is reinstalled. We do not auto-reinstall: surface an actionable error. |

### 4.8 Concurrency model

* Each pipeline is an `actor`. Internal state (current utterance buffer, last
  flush time) is `actor`-isolated.
* The two pipelines do not share mutable state other than the
  `ConversationContextActor`.
* Audio capture taps run on dedicated real-time threads (Core Audio's I/O
  proc and `AVAudioEngine`'s render thread). They publish frames into
  lock-free single-producer-single-consumer ring buffers; the pipelines'
  consumer tasks drain those buffers on Swift Concurrency.
* Network calls (Scribe WebSocket, Translator REST, Flash WebSocket) use
  `URLSession` with `async`/`await` and structured cancellation.

---

## 5. User interface

### 5.1 Menu bar item

`NSStatusItem` with an `NSImage` icon that reflects state:

* Gray microphone icon: app idle.
* Blue microphone icon: app armed but session not active.
* Animated waveform icon: session active.

Menu contents:

```
●  VoiceMiddle
─────────────────────────
◉ Active session (EN ↔ ES)
─────────────────────────
Source app:    Microsoft Teams ▼
Pace mode:     Turn-based ▼
Read-only inbound: ☐
─────────────────────────
⌥⌘V  Toggle session
Preferences…
Quit
```

The global hotkey (default ⌥⌘V) is registered via `NSEvent.addGlobalMonitor`
and can be rebound in Settings.

### 5.2 Floating HUD window

When a session is active and "Show HUD" is enabled, an `NSPanel` (`.floating`
level, non-key, semi-transparent) renders the live transcript. The window is
draggable, resizable, and remembers position per display.

Layout per turn:

```
┌──────────────────────────────────────────────────────────┐
│ ●  EN ↔ ES   Teams   Turn-based   ⏸                      │
├──────────────────────────────────────────────────────────┤
│ 🗣 OTHER (EN)                                14:32        │
│   "So what's your take on the timeline?"                 │
│   → ¿Cuál es tu opinión sobre el calendario?             │
├──────────────────────────────────────────────────────────┤
│ 🎙 ME (ES)                                  14:32         │
│   "Creo que es ajustado pero alcanzable."                │
│   → I think it's tight but achievable.                   │
├──────────────────────────────────────────────────────────┤
│ 🗣 OTHER (EN) … (in progress)                            │
└──────────────────────────────────────────────────────────┘
```

In "Read-only inbound" mode, the inbound side still renders the translation
but no TTS plays in the headphones.

### 5.3 Settings window

`Settings` scene with tabs:

* **General:** open at login, show HUD on session start, HUD opacity, global
  hotkey, accent color.
* **Languages:** source language, target language, swap button, voice preset
  per direction (with a "Preview" button that synthesizes a sample with the
  selected ElevenLabs voice).
* **Translation:** translator engine (Claude / GPT / DeepL), model selector,
  pace mode default per direction, API keys (stored in Keychain, shown
  redacted), endpoint override per provider.
* **Audio:** target app picker (live list of audio-producing processes),
  input device, output device, VAD sensitivity slider per direction,
  ducking mode (Off / Duck to level / Mute), ducking level slider,
  fade-in/fade-out duration.
* **Privacy:** "Save transcripts to disk" (default off), open transcript
  directory, clear all transcripts, links to system permission panes.

### 5.4 Onboarding

First-launch wizard, three steps:

1. **Welcome and permissions** — explains what VoiceMiddle does, walks
   through Microphone, Audio Capture, and System Extension installation.
2. **API keys** — fields for ElevenLabs and one of Anthropic / OpenAI /
   DeepL. Includes a "Test connection" button per service.
3. **Pick a target app** — list of currently audio-producing apps; pick one
   or skip and configure later.

---

## 6. Configuration and persistence

### 6.1 Settings store

* All non-secret settings: `UserDefaults` via a `@AppStorage`-backed
  `SettingsStore` `ObservableObject`. Strongly typed wrappers around each
  key.
* Secrets (API keys): macOS Keychain, accessed via a thin `KeychainService`
  helper. Keys are never read into UI plain text after entry; the field
  shows `••••••••`.

### 6.2 Transcripts

* Off by default.
* When enabled, transcripts are written to
  `~/Library/Application Support/VoiceMiddle/Transcripts/<session-id>.json`
  with one JSON object per turn (source text, translated text, direction,
  timestamps, voice and model identifiers).
* The Privacy tab offers a "Clear all transcripts" action and a "Reveal in
  Finder" button.

### 6.3 Schema versioning

Settings and transcript JSON files are versioned with a `schemaVersion` field
to allow future migrations. The MVP is `schemaVersion = 1`.

---

## 7. Permissions and entitlements

### 7.1 macOS permission prompts

| Prompt | Trigger | Info.plist key |
|---|---|---|
| Microphone access | First time `AVAudioEngine` opens the input node. | `NSMicrophoneUsageDescription` |
| Audio capture (process tap) | First time `AudioHardwareCreateProcessTap` is called. | `NSAudioCaptureUsageDescription` (macOS 14.6+) |
| System Extension install | When the user clicks "Install driver" in onboarding. | Handled by the System Extensions framework. |
| Accessibility | If the user enables the global hotkey for the first time. | `NSAccessibilityUsageDescription` |
| Network | Implicit; no prompt. | n/a |

### 7.2 Entitlements

The main app must be sandboxed and signed with:

* `com.apple.security.app-sandbox`
* `com.apple.security.system-extension.install`
* `com.apple.security.device.audio-input`
* `com.apple.security.network.client`

The driver must be signed with the AudioDriverKit DriverKit entitlement, which
Apple grants on request for virtual-audio-device products.

### 7.3 Notarization

The app and driver are both notarized. The driver is bundled inside the app
bundle's `Contents/Library/SystemExtensions/` and activated on first launch.

---

## 8. Logging, metrics, and diagnostics

* **Logging:** `os.Logger` per subsystem (`audio`, `pipeline`, `translator`,
  `stt`, `tts`, `ui`, `driver-bridge`). Default level: `info`. A "Diagnostic
  log" command in the Help menu opens Console.app filtered to VoiceMiddle.
* **Metrics:** in-process counters and EMA timing measurements
  (`PipelineMetrics`):
  * STT round-trip latency (ms), per direction.
  * Translator latency (ms), per direction.
  * TTS time-to-first-chunk (ms), per direction.
  * End-to-end latency from end-of-utterance to TTS playback start.
  * Reconnect counts per service.
* Metrics are visible in a hidden Diagnostics window opened via
  ⌥⌘D for debugging; they are not transmitted off-device.

---

## 9. Testing strategy

* **Unit tests** for the deterministic components: `TranscriptAggregator`,
  `VAD`, `ConversationContextActor`, `SettingsStore`, `KeychainService`.
* **Translator contract tests:** a shared `XCTest` test suite parameterized
  by `Translator` implementation that uses canned source utterances and
  asserts on round-trip latency, fallback behaviour, and context handling
  (where supported).
* **STT and TTS clients:** mocked at the WebSocket frame level using a local
  test server that replays canned scripts; we do not call the live
  ElevenLabs API in CI.
* **Audio pipeline integration tests:** feed pre-recorded mono PCM into the
  pipeline's audio source mock and assert that the expected sequence of
  events fires on the sink.
* **Driver smoke test:** a script that installs the driver, opens it as an
  input device via AVFoundation, writes a known sine wave, and asserts the
  reader sees that sine wave.
* **Manual test plan** for each release: hit each communication app on the
  support matrix (Teams, Meet, Slack, Zoom, FaceTime, Discord), validate
  bidirectional translation, validate ducking, validate read-only mode,
  validate hotkey toggle.

---

## 10. Roadmap and phasing

The project is built in five phases. Each phase ends with a runnable
milestone.

### Phase 1 — Skeleton and audio plumbing (target: 2 weeks)

* Xcode project with `VoiceMiddle.app` and `VoiceMiddleDriver` targets.
* Driver registers a "VoiceMiddle Mic" device system-wide, but only writes
  silence.
* Main app captures audio from the system default microphone and writes it
  into the driver. Communication apps see the user's untranslated voice on
  VoiceMiddle Mic. **No translation yet.**
* Settings stub for picking input/output devices.

### Phase 2 — Inbound pipeline (target: 2 weeks)

* Core Audio Process Tap on a target communication app.
* `ScribeV2StreamClient` end to end.
* `ClaudeTranslator` end to end.
* `FlashV2StreamClient` end to end.
* Playback to headphones with manual ducking (constant −20 dB while TTS
  plays, no fade).
* **Demo milestone:** the user can hear a friend speaking English in a
  Google Meet call translated to Spanish in real time.

### Phase 3 — Outbound pipeline and HUD (target: 2 weeks)

* Pipeline B→A wired up; translated audio is written into the driver.
* Floating HUD window with live transcript for both directions.
* Onboarding wizard (permissions and API keys).
* **Demo milestone:** full bidirectional translation between two people on a
  Google Meet call, with the other party hearing the user's translated
  voice without installing anything.

### Phase 4 — Configurability and polish (target: 2 weeks)

* Add `GPTTranslator` and `DeepLTranslator`.
* Streaming pace mode.
* Read-only inbound mode.
* Configurable ducking (off / duck / mute, dB slider, fade duration).
* Settings window with all tabs.
* Keychain integration for API keys.

### Phase 5 — Diagnostics, packaging, and release (target: 2 weeks)

* `PipelineMetrics` and the Diagnostics window.
* Notarization and signed installer (`.dmg`).
* Crash reporting hooks.
* Manual test pass on the full communication-app matrix.
* Public release.

### Post-MVP enhancements (not committed)

* Voice cloning (drop-in replacement for `FlashV2StreamClient` with a clone-
  capable client; UX flow for capturing voice samples on consent).
* Custom domain vocabularies per session (medical, legal, software).
* Live edit of the transcript with re-translation.
* Windows and Linux ports (the `Translator`, `STTStreamClient`, and
  `TTSStreamClient` abstractions are designed to be portable; the audio
  capture and virtual device modules are necessarily reimplemented per
  platform).

---

## 11. Open questions

1. **Pricing model.** ElevenLabs and Anthropic/OpenAI/DeepL costs are
   per-character / per-second. We need to surface real-time cost estimates
   to the user during a session. Out of scope for the design but flagged.
2. **Echo handling.** If the user's headphones leak the translated audio
   into the microphone, the outbound pipeline could pick up its own
   inbound translation. AVAudioEngine's echo cancellation
   (`voiceProcessing`) is one option; revisit during Phase 3.
3. **Driver activation UX after macOS upgrades.** If the user upgrades
   macOS, the driver may need to be re-approved. Need a clear in-app flow
   to detect and prompt for this.
4. **Identity of the speaker on the inbound side.** With Process Taps, we
   capture the mixed output of the app; if there are multiple remote
   speakers in a Meet call, Scribe will transcribe them all as a single
   stream. Diarization is not in scope for MVP, but the HUD should
   visually mark this is a single "OTHER" channel and may include
   multiple voices.

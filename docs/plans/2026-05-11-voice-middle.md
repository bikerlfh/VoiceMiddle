# VoiceMiddle Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ship a macOS 14.6+ app that translates a two-party voice/video call in
real time, bidirectionally, on top of ElevenLabs Scribe v2 + Flash v2.5, with a
DriverKit virtual microphone that any communication app can pick up.

**Architecture:** A SwiftUI macOS app drives two independent translation
pipelines (inbound and outbound), each composed of an STT stream client (Scribe),
a pluggable translator (Claude / GPT / DeepL), and a TTS stream client (Flash).
Audio is captured via Core Audio Process Taps for the target communication app
and `AVAudioEngine` for the user microphone; outbound translated audio is
written into a virtual input device exposed by a bundled DriverKit System
Extension. Most logic lives in testable Swift Package Manager modules so the
app and driver remain thin shells.

**Tech Stack:** Swift 5.10 / Swift 6 mode, SwiftUI, Swift Concurrency
(`actor`, `async`/`await`, `AsyncStream`), `AVFoundation`, Core Audio Process
Taps, `AudioDriverKit`, Swift Testing, `URLSession` (WebSocket and REST), Swift
Package Manager.

**Source layout (target):**

```
voice-in-the-middle/
├── Package.swift                ← root SwiftPM workspace
├── Sources/
│   ├── VMCore/                  ← shared models, settings, context actor
│   ├── VMAudio/                 ← AVAudioEngine, Core Audio Taps, ring buffer
│   ├── VMScribe/                ← Scribe v2 realtime WebSocket client
│   ├── VMFlash/                 ← Flash v2.5 WebSocket client
│   ├── VMTranslators/           ← Translator protocol + Claude/GPT/DeepL
│   └── VMPipeline/              ← orchestration, VAD, aggregator
├── Tests/
│   ├── VMCoreTests/
│   ├── VMAudioTests/
│   ├── VMScribeTests/
│   ├── VMFlashTests/
│   ├── VMTranslatorsTests/
│   └── VMPipelineTests/
├── VoiceMiddle.xcworkspace
├── VoiceMiddle/                 ← Xcode app target
│   ├── App/                     ← @main, AppDelegate, menu bar
│   ├── Settings/                ← SwiftUI settings scene
│   ├── HUD/                     ← floating transcript window
│   └── Onboarding/              ← first-launch wizard
└── VoiceMiddleDriver/           ← DriverKit Xcode project
```

**Engineering principles for this plan:**

* **Test-driven where useful.** Pure-logic modules (`VMCore`, `VMTranslators`,
  `VMPipeline`) follow strict red-green-refactor with Swift Testing. Real-time
  audio and driver code uses smoke tests with canned PCM rather than unit
  tests — the verification step in each task spells out the manual check.
* **Frequent commits.** Each task ends with a commit using the conventional
  format from the user's commit rules (no `Co-Authored-By`, no `--gpg-sign`,
  conventional `type(scope): subject` + bulleted body).
* **English only.** Every identifier, comment, doc, and commit message is in
  English. Replies in chat may be in Spanish.
* **Senior-level Swift.** Prefer `actor`, structured concurrency,
  `AsyncStream`, `Sendable`. No GCD unless interfacing with C APIs. No
  callbacks in new public API. No allocations on audio threads.

**Verification command shortcuts used below:**

* `swift test --package-path .` — run all SwiftPM tests.
* `swift test --filter <SuiteName>` — run one suite.
* `xcodebuild test -workspace VoiceMiddle.xcworkspace -scheme VoiceMiddle -destination 'platform=macOS'` — run Xcode-target tests.

---

## Phase 0 — Project bootstrap

### Task 0.1: Initialize git repository and base files

**Files:**
- Create: `.gitignore`
- Create: `.gitattributes`

**Step 1: Initialize git**

```bash
cd /Users/luismo/Documents/projects/voice-in-the-middle
git init -b main
```

**Step 2: Write `.gitignore`**

```gitignore
# Xcode
build/
DerivedData/
*.xcuserstate
xcuserdata/
*.xcworkspace/xcuserdata/
*.xcodeproj/xcuserdata/
*.xcodeproj/project.xcworkspace/xcuserdata/

# SwiftPM
.build/
.swiftpm/
Package.resolved

# macOS
.DS_Store

# Logs and dumps
*.log
*.dmp

# Secrets
.env
.env.*
*.p12
*.cer
*.mobileprovision
*.provisionprofile
```

**Step 3: Write `.gitattributes`**

```
* text=auto eol=lf
*.png binary
*.jpg binary
*.pdf binary
*.dmg binary
```

**Step 4: Stage and verify**

```bash
git add .gitignore .gitattributes README.md docs/
git status
```
Expected: `README.md`, `docs/design.md`, `docs/plans/2026-05-11-voice-middle.md`,
`.gitignore`, `.gitattributes` all staged as new files.

**Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
chore(repo): initialize repository with design spec and plan

- Add .gitignore and .gitattributes
- Include README and docs/design.md (approved spec)
- Include docs/plans/2026-05-11-voice-middle.md
EOF
)"
```

---

### Task 0.2: Create the root SwiftPM workspace

**Files:**
- Create: `Package.swift`
- Create: `Sources/VMCore/Placeholder.swift` (temporary, replaced in 1.1)
- Create: `Tests/VMCoreTests/PlaceholderTests.swift` (temporary)

**Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "VoiceMiddle",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VMCore", targets: ["VMCore"]),
        .library(name: "VMAudio", targets: ["VMAudio"]),
        .library(name: "VMScribe", targets: ["VMScribe"]),
        .library(name: "VMFlash", targets: ["VMFlash"]),
        .library(name: "VMTranslators", targets: ["VMTranslators"]),
        .library(name: "VMPipeline", targets: ["VMPipeline"]),
    ],
    targets: [
        .target(name: "VMCore"),
        .target(name: "VMAudio", dependencies: ["VMCore"]),
        .target(name: "VMScribe", dependencies: ["VMCore"]),
        .target(name: "VMFlash", dependencies: ["VMCore"]),
        .target(name: "VMTranslators", dependencies: ["VMCore"]),
        .target(name: "VMPipeline", dependencies: [
            "VMCore", "VMAudio", "VMScribe", "VMFlash", "VMTranslators",
        ]),
        .testTarget(name: "VMCoreTests", dependencies: ["VMCore"]),
        .testTarget(name: "VMAudioTests", dependencies: ["VMAudio"]),
        .testTarget(name: "VMScribeTests", dependencies: ["VMScribe"]),
        .testTarget(name: "VMFlashTests", dependencies: ["VMFlash"]),
        .testTarget(name: "VMTranslatorsTests", dependencies: ["VMTranslators"]),
        .testTarget(name: "VMPipelineTests", dependencies: ["VMPipeline"]),
    ],
    swiftLanguageVersions: [.v5]
)
```

**Step 2: Add placeholder source so the package compiles**

`Sources/VMCore/Placeholder.swift`:
```swift
// Replaced in Task 1.1 with real types.
enum _VMCorePlaceholder {}
```

`Tests/VMCoreTests/PlaceholderTests.swift`:
```swift
import Testing

@Suite("Placeholder")
struct PlaceholderTests {
    @Test func packageBuilds() {
        #expect(true)
    }
}
```
For every other test target, add one trivial placeholder test of the same
shape so all targets compile.

**Step 3: Verify build**

Run: `swift build`
Expected: builds with no errors.

Run: `swift test`
Expected: 6 trivial tests pass.

**Step 4: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "$(cat <<'EOF'
chore(spm): scaffold root SwiftPM workspace with six module targets

- Add VMCore, VMAudio, VMScribe, VMFlash, VMTranslators, VMPipeline targets
- Add matching test targets with placeholder tests
- Pin to macOS 14
EOF
)"
```

---

### Task 0.3: Create CI script for local verification

**Files:**
- Create: `scripts/check.sh`

**Step 1: Write the script**

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> swift build"
swift build

echo "==> swift test"
swift test --parallel

echo "==> swift format lint"
if command -v swift-format >/dev/null 2>&1; then
    swift-format lint --recursive Sources Tests
else
    echo "swift-format not installed, skipping lint"
fi

echo "All checks passed."
```

**Step 2: Make executable**

```bash
chmod +x scripts/check.sh
```

**Step 3: Verify**

```bash
./scripts/check.sh
```
Expected: build, tests, lint (or skip) all succeed.

**Step 4: Commit**

```bash
git add scripts/check.sh
git commit -m "$(cat <<'EOF'
chore(ci): add local check.sh script for build, test, lint

- Runs swift build, swift test, optional swift-format lint
- Used as the single quality gate before commits
EOF
)"
```

---

## Phase 1 — Skeleton and audio plumbing

### Task 1.1: Define shared domain types in VMCore

**Files:**
- Create: `Sources/VMCore/Direction.swift`
- Create: `Sources/VMCore/LanguageCode.swift`
- Create: `Sources/VMCore/VoiceID.swift`
- Create: `Sources/VMCore/AudioFormat.swift`
- Create: `Tests/VMCoreTests/LanguageCodeTests.swift`
- Delete: `Sources/VMCore/Placeholder.swift`
- Delete: `Tests/VMCoreTests/PlaceholderTests.swift`

**Step 1: Write the failing test**

`Tests/VMCoreTests/LanguageCodeTests.swift`:
```swift
import Testing
@testable import VMCore

@Suite("LanguageCode")
struct LanguageCodeTests {
    @Test("BCP-47 strings round-trip")
    func roundTrip() throws {
        let code = try LanguageCode("en-US")
        #expect(code.rawValue == "en-US")
        #expect(code.primarySubtag == "en")
    }

    @Test("Invalid strings throw")
    func invalidThrows() {
        #expect(throws: LanguageCode.Error.self) {
            _ = try LanguageCode("")
        }
    }

    @Test("Primary subtag is lowercased")
    func primarySubtagLowercased() throws {
        let code = try LanguageCode("EN")
        #expect(code.primarySubtag == "en")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter LanguageCodeTests`
Expected: FAIL — `LanguageCode` not defined.

**Step 3: Write the types**

`Sources/VMCore/Direction.swift`:
```swift
/// Direction of a translation pipeline relative to the local user.
///
/// `inbound` carries audio from the remote party into the user's headphones.
/// `outbound` carries audio from the user's microphone into the virtual
/// microphone consumed by the communication app.
public enum Direction: String, Sendable, CaseIterable, Hashable {
    case inbound
    case outbound
}
```

`Sources/VMCore/LanguageCode.swift`:
```swift
/// A BCP-47 language code such as `en` or `en-US`.
///
/// Validation here is intentionally light: we accept any non-empty string of
/// ASCII letters and hyphens. Upstream APIs (Scribe, translators) perform the
/// authoritative validation.
public struct LanguageCode: Hashable, Sendable, CustomStringConvertible {
    public enum Error: Swift.Error, Equatable { case invalid(String) }

    public let rawValue: String
    public let primarySubtag: String

    public init(_ rawValue: String) throws {
        let trimmed = rawValue.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              trimmed.allSatisfy({ $0.isASCII && ($0.isLetter || $0 == "-") })
        else { throw Error.invalid(rawValue) }
        self.rawValue = trimmed
        self.primarySubtag = trimmed.split(separator: "-").first.map {
            $0.lowercased()
        } ?? trimmed.lowercased()
    }

    public var description: String { rawValue }
}
```

`Sources/VMCore/VoiceID.swift`:
```swift
/// Opaque identifier for an ElevenLabs voice.
public struct VoiceID: Hashable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
}
```

`Sources/VMCore/AudioFormat.swift`:
```swift
/// Canonical PCM format used across the project: 48 kHz, mono, 32-bit float,
/// non-interleaved.
public enum CanonicalAudioFormat {
    public static let sampleRate: Double = 48_000
    public static let channelCount: UInt32 = 1
    public static let bitsPerChannel: UInt32 = 32
}
```

Delete `Sources/VMCore/Placeholder.swift` and
`Tests/VMCoreTests/PlaceholderTests.swift`.

**Step 4: Run test to verify it passes**

Run: `swift test --filter LanguageCodeTests`
Expected: PASS, 3 tests.

**Step 5: Commit**

```bash
git add Sources/VMCore Tests/VMCoreTests
git commit -m "$(cat <<'EOF'
feat(vmcore): add shared domain types Direction, LanguageCode, VoiceID

- LanguageCode validates BCP-47 strings and exposes primary subtag
- Direction enum for pipeline orientation
- VoiceID as opaque ElevenLabs voice identifier
- AudioFormat constants pin 48 kHz / mono / Float32
EOF
)"
```

---

### Task 1.2: Conversation context actor

**Files:**
- Create: `Sources/VMCore/ConversationContext.swift`
- Create: `Sources/VMCore/ConversationContextActor.swift`
- Create: `Tests/VMCoreTests/ConversationContextActorTests.swift`

**Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import VMCore

@Suite("ConversationContextActor")
struct ConversationContextActorTests {
    @Test("Caps history at the configured size")
    func capsHistory() async throws {
        let actor = ConversationContextActor(maxTurns: 3)
        for i in 0..<5 {
            await actor.appendTurn(.init(
                direction: .inbound,
                original: "src \(i)",
                translated: "dst \(i)",
                timestamp: Date()))
        }
        let snapshot = await actor.snapshot(topicHint: nil)
        #expect(snapshot.recentTurns.count == 3)
        #expect(snapshot.recentTurns.first?.original == "src 2")
        #expect(snapshot.recentTurns.last?.original == "src 4")
    }

    @Test("Snapshot is independent of subsequent mutations")
    func snapshotIndependent() async throws {
        let actor = ConversationContextActor(maxTurns: 5)
        await actor.appendTurn(.init(
            direction: .inbound, original: "a", translated: "A",
            timestamp: Date()))
        let snapshot = await actor.snapshot(topicHint: nil)
        await actor.appendTurn(.init(
            direction: .inbound, original: "b", translated: "B",
            timestamp: Date()))
        #expect(snapshot.recentTurns.count == 1)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter ConversationContextActorTests`
Expected: FAIL — types not defined.

**Step 3: Implement**

`Sources/VMCore/ConversationContext.swift`:
```swift
import Foundation

public struct ConversationContext: Sendable, Equatable {
    public struct Turn: Sendable, Equatable {
        public let direction: Direction
        public let original: String
        public let translated: String
        public let timestamp: Date
        public init(direction: Direction, original: String,
                    translated: String, timestamp: Date) {
            self.direction = direction
            self.original = original
            self.translated = translated
            self.timestamp = timestamp
        }
    }

    public let recentTurns: [Turn]
    public let sessionTopicHint: String?

    public init(recentTurns: [Turn], sessionTopicHint: String?) {
        self.recentTurns = recentTurns
        self.sessionTopicHint = sessionTopicHint
    }
}
```

`Sources/VMCore/ConversationContextActor.swift`:
```swift
/// Thread-safe rolling buffer of conversation turns shared by both pipelines.
///
/// Pipelines append after each successful translation; translators take a
/// snapshot at request time. Snapshots are immutable values, so appending
/// after a snapshot has been taken does not affect the in-flight request.
public actor ConversationContextActor {
    private var turns: [ConversationContext.Turn] = []
    private let maxTurns: Int

    public init(maxTurns: Int = 6) {
        precondition(maxTurns > 0)
        self.maxTurns = maxTurns
    }

    public func appendTurn(_ turn: ConversationContext.Turn) {
        turns.append(turn)
        if turns.count > maxTurns {
            turns.removeFirst(turns.count - maxTurns)
        }
    }

    public func snapshot(topicHint: String?) -> ConversationContext {
        ConversationContext(recentTurns: turns, sessionTopicHint: topicHint)
    }

    public func clear() { turns.removeAll(keepingCapacity: true) }
}
```

**Step 4: Run test**

Run: `swift test --filter ConversationContextActorTests`
Expected: PASS, 2 tests.

**Step 5: Commit**

```bash
git add Sources/VMCore Tests/VMCoreTests
git commit -m "$(cat <<'EOF'
feat(vmcore): add ConversationContext value type and rolling-buffer actor

- ConversationContext.Turn carries both source and translated text
- ConversationContextActor caps history at maxTurns (default 6)
- Snapshot is a value so concurrent appends don't mutate in-flight payloads
EOF
)"
```

---

### Task 1.3: Lock-free single-producer single-consumer ring buffer

**Files:**
- Create: `Sources/VMAudio/RingBuffer.swift`
- Create: `Tests/VMAudioTests/RingBufferTests.swift`

**Step 1: Write the failing test**

```swift
import Testing
@testable import VMAudio

@Suite("RingBuffer")
struct RingBufferTests {
    @Test("Write then read recovers all bytes")
    func writeRead() {
        let buffer = RingBuffer(capacity: 1024)
        let input: [Float] = (0..<256).map(Float.init)
        let written = input.withUnsafeBufferPointer {
            buffer.write($0.baseAddress!, count: $0.count)
        }
        #expect(written == 256)

        var output = [Float](repeating: 0, count: 256)
        let read = output.withUnsafeMutableBufferPointer {
            buffer.read($0.baseAddress!, count: $0.count)
        }
        #expect(read == 256)
        #expect(output == input)
    }

    @Test("Write past capacity refuses excess")
    func overflowRefused() {
        let buffer = RingBuffer(capacity: 4)
        let input: [Float] = [1, 2, 3, 4, 5]
        let written = input.withUnsafeBufferPointer {
            buffer.write($0.baseAddress!, count: $0.count)
        }
        #expect(written == 4)
    }

    @Test("Read from empty returns zero")
    func emptyRead() {
        let buffer = RingBuffer(capacity: 16)
        var output = [Float](repeating: -1, count: 8)
        let read = output.withUnsafeMutableBufferPointer {
            buffer.read($0.baseAddress!, count: $0.count)
        }
        #expect(read == 0)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter RingBufferTests`
Expected: FAIL — `RingBuffer` not defined.

**Step 3: Implement**

`Sources/VMAudio/RingBuffer.swift`:
```swift
import Atomics
import Foundation

/// Single-producer single-consumer lock-free ring buffer of `Float` samples.
///
/// Suitable for shuttling PCM frames from a Core Audio I/O proc on the
/// real-time audio thread to a Swift Concurrency consumer task. The writer
/// must be a single thread; the reader must be a single thread; they may
/// differ.
///
/// Bytes are not allocated after construction. The buffer never blocks; if
/// the writer can't fit all incoming samples, it writes as many as it can
/// and returns the count actually written.
public final class RingBuffer: @unchecked Sendable {
    private let storage: UnsafeMutableBufferPointer<Float>
    private let mask: Int
    private let head = ManagedAtomic<Int>(0)   // write index
    private let tail = ManagedAtomic<Int>(0)   // read index

    /// - Parameter capacity: rounded up to the next power of two.
    public init(capacity: Int) {
        let rounded = max(2, capacity.nextPowerOfTwo)
        let raw = UnsafeMutablePointer<Float>.allocate(capacity: rounded)
        raw.initialize(repeating: 0, count: rounded)
        self.storage = UnsafeMutableBufferPointer(start: raw, count: rounded)
        self.mask = rounded - 1
    }

    deinit {
        storage.baseAddress?.deinitialize(count: storage.count)
        storage.baseAddress?.deallocate()
    }

    /// Writes up to `count` samples. Returns the count actually written.
    /// Safe on the audio thread; never allocates, never blocks.
    @discardableResult
    public func write(_ source: UnsafePointer<Float>, count: Int) -> Int {
        let h = head.load(ordering: .relaxed)
        let t = tail.load(ordering: .acquiring)
        let free = storage.count - (h &- t)
        let n = Swift.min(count, free)
        for i in 0..<n {
            storage[(h &+ i) & mask] = source[i]
        }
        head.store(h &+ n, ordering: .releasing)
        return n
    }

    /// Reads up to `count` samples. Returns the count actually read.
    @discardableResult
    public func read(_ destination: UnsafeMutablePointer<Float>,
                     count: Int) -> Int {
        let t = tail.load(ordering: .relaxed)
        let h = head.load(ordering: .acquiring)
        let available = h &- t
        let n = Swift.min(count, available)
        for i in 0..<n {
            destination[i] = storage[(t &+ i) & mask]
        }
        tail.store(t &+ n, ordering: .releasing)
        return n
    }

    public var approximateCount: Int {
        head.load(ordering: .relaxed) &- tail.load(ordering: .relaxed)
    }
}

private extension Int {
    var nextPowerOfTwo: Int {
        guard self > 1 else { return 1 }
        return 1 << (Int.bitWidth - (self - 1).leadingZeroBitCount)
    }
}
```

Add `swift-atomics` as a dependency in `Package.swift`:
```swift
.package(url: "https://github.com/apple/swift-atomics.git", from: "1.2.0"),
```
and:
```swift
.target(name: "VMAudio", dependencies: [
    "VMCore",
    .product(name: "Atomics", package: "swift-atomics"),
]),
```

**Step 4: Run test**

Run: `swift test --filter RingBufferTests`
Expected: PASS, 3 tests.

**Step 5: Commit**

```bash
git add Sources/VMAudio Tests/VMAudioTests Package.swift
git commit -m "$(cat <<'EOF'
feat(vmaudio): add lock-free SPSC ring buffer for real-time audio

- Power-of-two storage with acquire/release atomics on head and tail
- No allocations after construction; safe to use from Core Audio I/O procs
- Add swift-atomics dependency
EOF
)"
```

---

### Task 1.4: Settings store skeleton

**Files:**
- Create: `Sources/VMCore/Settings/SettingsStore.swift`
- Create: `Sources/VMCore/Settings/PaceMode.swift`
- Create: `Sources/VMCore/Settings/DuckingMode.swift`
- Create: `Tests/VMCoreTests/SettingsStoreTests.swift`

**Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import VMCore

@Suite("SettingsStore")
struct SettingsStoreTests {
    @Test("Defaults match the spec")
    func defaults() {
        let store = SettingsStore(defaults: UserDefaults(
            suiteName: UUID().uuidString)!)
        #expect(store.paceMode(for: .inbound) == .turnBased)
        #expect(store.paceMode(for: .outbound) == .turnBased)
        #expect(store.readOnlyInbound == false)
        #expect(store.duckingMode == .duckToLevel)
        #expect(abs(store.duckingLevelDB - (-20)) < 0.01)
    }

    @Test("Per-direction pace mode round-trips")
    func paceRoundTrip() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let a = SettingsStore(defaults: defaults)
        a.setPaceMode(.streaming, for: .inbound)
        let b = SettingsStore(defaults: defaults)
        #expect(b.paceMode(for: .inbound) == .streaming)
        #expect(b.paceMode(for: .outbound) == .turnBased)
    }
}
```

**Step 2: Run test to verify it fails**

Expected: FAIL — types not defined.

**Step 3: Implement**

`Sources/VMCore/Settings/PaceMode.swift`:
```swift
public enum PaceMode: String, Sendable, CaseIterable {
    case turnBased, streaming
}
```

`Sources/VMCore/Settings/DuckingMode.swift`:
```swift
public enum DuckingMode: String, Sendable, CaseIterable {
    case off, duckToLevel, mute
}
```

`Sources/VMCore/Settings/SettingsStore.swift`:
```swift
import Foundation

/// Persists user-visible settings. Backed by `UserDefaults` so it works on the
/// main app, the test bundle, and any helper tool. API keys do NOT live here;
/// see ``KeychainService``.
public final class SettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private enum Key: String {
        case paceInbound, paceOutbound
        case readOnlyInbound
        case duckingMode, duckingLevelDB
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: pace mode
    public func paceMode(for direction: Direction) -> PaceMode {
        let key = direction == .inbound ? Key.paceInbound : .paceOutbound
        return defaults.string(forKey: key.rawValue)
            .flatMap(PaceMode.init(rawValue:)) ?? .turnBased
    }
    public func setPaceMode(_ mode: PaceMode, for direction: Direction) {
        let key = direction == .inbound ? Key.paceInbound : .paceOutbound
        defaults.set(mode.rawValue, forKey: key.rawValue)
    }

    // MARK: read-only inbound
    public var readOnlyInbound: Bool {
        get { defaults.bool(forKey: Key.readOnlyInbound.rawValue) }
        set { defaults.set(newValue, forKey: Key.readOnlyInbound.rawValue) }
    }

    // MARK: ducking
    public var duckingMode: DuckingMode {
        get {
            defaults.string(forKey: Key.duckingMode.rawValue)
                .flatMap(DuckingMode.init(rawValue:)) ?? .duckToLevel
        }
        set { defaults.set(newValue.rawValue, forKey: Key.duckingMode.rawValue) }
    }
    public var duckingLevelDB: Double {
        get {
            defaults.object(forKey: Key.duckingLevelDB.rawValue) as? Double
                ?? -20.0
        }
        set { defaults.set(newValue, forKey: Key.duckingLevelDB.rawValue) }
    }
}
```

**Step 4: Run test**

Run: `swift test --filter SettingsStoreTests`
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/VMCore Tests/VMCoreTests
git commit -m "$(cat <<'EOF'
feat(vmcore): add SettingsStore with pace, read-only, ducking defaults

- Per-direction PaceMode persistence
- DuckingMode enum (off / duckToLevel / mute) with default duckToLevel
- Ducking level dB defaults to -20
- UserDefaults injection makes it testable per suite
EOF
)"
```

---

### Task 1.5: Keychain helper for API keys

**Files:**
- Create: `Sources/VMCore/Settings/KeychainService.swift`
- Create: `Tests/VMCoreTests/KeychainServiceTests.swift`

Follow the same 5-step structure:

* Test: set, retrieve, delete, isolated by service+account string.
* Implement using `SecItemAdd`/`SecItemCopyMatching`/`SecItemDelete` with
  `kSecClassGenericPassword`. Service string is parameterized so each test
  uses a unique service.
* Commit: `feat(vmcore): add KeychainService for API key storage`.

---

### Task 1.6: Bootstrap the Xcode workspace and app target

**Files:**
- Create: `VoiceMiddle.xcworkspace` (via Xcode UI)
- Create: `VoiceMiddle/VoiceMiddle.xcodeproj` (App target)
- Create: `VoiceMiddle/App/VoiceMiddleApp.swift`
- Create: `VoiceMiddle/App/AppDelegate.swift`
- Create: `VoiceMiddle/Info.plist`
- Create: `VoiceMiddle/VoiceMiddle.entitlements`

**Step 1: Create the workspace and project in Xcode**

* `File → New → Workspace…` at the repo root, save as `VoiceMiddle.xcworkspace`.
* Add a new macOS App project named `VoiceMiddle` into the workspace.
  Interface: SwiftUI, Language: Swift, Tests: yes, Bundle ID:
  `com.luismo.voicemiddle`.
* Add the root SwiftPM package to the workspace: `File → Add Packages → Add
  Local…`, point to the repo root.
* In the `VoiceMiddle` target → General → Frameworks: link `VMCore`,
  `VMAudio`, `VMScribe`, `VMFlash`, `VMTranslators`, `VMPipeline`.
* Set deployment target to macOS 14.6.

**Step 2: Write the SwiftUI app entry point**

`VoiceMiddle/App/VoiceMiddleApp.swift`:
```swift
import SwiftUI

@main
struct VoiceMiddleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
```

`VoiceMiddle/App/AppDelegate.swift`:
```swift
import AppKit

/// Hosts the menu bar item and any other AppKit-only singletons.
/// Real menu bar wiring lands in Task 1.7.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
```

**Step 3: Entitlements**

`VoiceMiddle/VoiceMiddle.entitlements`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key><true/>
    <key>com.apple.security.device.audio-input</key><true/>
    <key>com.apple.security.network.client</key><true/>
    <key>com.apple.security.system-extension.install</key><true/>
</dict>
</plist>
```

`Info.plist` additions:
* `LSUIElement = YES` (menu bar app, no Dock icon)
* `NSMicrophoneUsageDescription = "VoiceMiddle captures your microphone to translate your voice in real time."`
* `NSAudioCaptureUsageDescription = "VoiceMiddle taps the selected app's audio output to translate the other party's voice."`

**Step 4: Verify build**

`xcodebuild build -workspace VoiceMiddle.xcworkspace -scheme VoiceMiddle -destination 'platform=macOS' | xcpretty`
Expected: succeeds.

Launch the app from Xcode — it should run as an accessory app (no Dock
icon) and idle.

**Step 5: Commit**

```bash
git add VoiceMiddle VoiceMiddle.xcworkspace
git commit -m "$(cat <<'EOF'
feat(app): bootstrap VoiceMiddle Xcode app target as menu bar accessory

- Create Xcode workspace and macOS app project
- Link six SwiftPM modules
- Configure sandbox, audio-input, network, system-extension entitlements
- Add Info.plist usage strings for microphone and audio capture
- LSUIElement set so the app stays in the menu bar without a Dock icon
EOF
)"
```

---

### Task 1.7: Menu bar item and session state machine stub

**Files:**
- Create: `VoiceMiddle/App/MenuBarController.swift`
- Create: `VoiceMiddle/App/SessionController.swift`

**Step 1–4: Write the test for `SessionController` state transitions**

`Tests/VMPipelineTests/SessionControllerTests.swift` (move
`SessionController` to a SwiftPM module so it's testable, then re-import in
the app):
```swift
import Testing
@testable import VMPipeline

@Suite("SessionController")
struct SessionControllerTests {
    @Test("Start transitions idle → active and stop transitions back")
    func startStop() async {
        let controller = SessionController()
        #expect(controller.state == .idle)
        await controller.start()
        #expect(controller.state == .active)
        await controller.stop()
        #expect(controller.state == .idle)
    }
}
```

Implement `SessionController` as an `actor` in `VMPipeline` with `.idle`,
`.starting`, `.active`, `.stopping` states, an `async` `start()` /
`stop()` API, and an `AsyncStream<State>` for observers.

The `MenuBarController` in the app target reads the state via the
async stream and updates the `NSStatusItem` icon and menu accordingly.

**Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(app): add menu bar item and SessionController state machine

- SessionController (actor) drives idle/starting/active/stopping transitions
- MenuBarController binds NSStatusItem to SessionController state stream
- Menu has placeholder entries for source app, pace mode, preferences, quit
EOF
)"
```

---

### Task 1.8: Bootstrap the DriverKit System Extension project

**Files:**
- Create: `VoiceMiddleDriver/VoiceMiddleDriver.xcodeproj` (via Xcode template)
- Create: `VoiceMiddleDriver/VoiceMiddleDriver/VoiceMiddleDriver.cpp`
- Create: `VoiceMiddleDriver/VoiceMiddleDriver/VoiceMiddleDriver.iig`
- Create: `VoiceMiddleDriver/VoiceMiddleDriver/Info.plist`
- Create: `VoiceMiddleDriver/VoiceMiddleDriver/VoiceMiddleDriver.entitlements`

**Step 1: Create the DriverKit project**

* In Xcode: `File → New → Project → macOS → AudioDriverKit → Driver`.
* Save inside `VoiceMiddleDriver/`. Add it to the workspace.
* Bundle ID: `com.luismo.voicemiddle.driver`.
* Entitlements: `com.apple.developer.driverkit`,
  `com.apple.developer.driverkit.transport.audio`,
  `com.apple.developer.driverkit.userclient-access` with the app bundle ID
  listed.

**Step 2: Define the driver class skeleton (silent device)**

The Xcode template creates a class deriving from `IOUserAudioDevice`. Keep
its default behaviour for now: a single input stream of 48 kHz / mono /
Float32, returning zeros. This is the placeholder until Task 3.1.

**Step 3: Embed the driver inside the app's Contents/Library/SystemExtensions**

In the app target's Build Phases:
* Add a `Copy Files` phase with destination `SystemExtensions` and the
  driver as the bundled item.
* Add the driver target as a dependency of the app target.

**Step 4: Verify the driver builds**

`xcodebuild build -workspace VoiceMiddle.xcworkspace -scheme VoiceMiddleDriver -destination 'platform=macOS'`
Expected: succeeds.

**Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(driver): bootstrap DriverKit System Extension target

- AudioDriverKit driver skeleton from Apple template
- DriverKit entitlements for audio transport and userclient access
- App target embeds the driver via Copy Files build phase
EOF
)"
```

---

### Task 1.9: System extension installer in the app

**Files:**
- Create: `VoiceMiddle/Driver/SystemExtensionInstaller.swift`
- Create: `VoiceMiddle/Driver/VirtualMicClient.swift`

**Step 1–4:** Implement `SystemExtensionInstaller` as an `actor` that wraps
`OSSystemExtensionManager` and exposes:
```swift
public actor SystemExtensionInstaller {
    public enum Status: Sendable { case notInstalled, needsApproval,
        installed, error(String) }

    public func currentStatus() async -> Status
    public func install() async throws       // throws on rejection
}
```

Hook a "Install driver…" button into a temporary onboarding screen so it can
be triggered manually. After installation, verify that the driver appears
in `Audio MIDI Setup` and in the Sound preference pane.

**Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(app): add SystemExtensionInstaller actor for driver activation

- Wraps OSSystemExtensionManager request flow
- Exposes status (notInstalled, needsApproval, installed, error)
- Temporary onboarding screen triggers install
EOF
)"
```

---

### Task 1.10: Microphone capture writes into the virtual mic

**Files:**
- Create: `Sources/VMAudio/MicrophoneCapture.swift`
- Create: `VoiceMiddle/Driver/VirtualMicClient.swift` (XPC sender)
- Create: `Tests/VMAudioTests/MicrophoneCaptureTests.swift` (smoke)

**Step 1: Implement `MicrophoneCapture`**

```swift
import AVFoundation

/// Captures the system default microphone at 48 kHz mono and pushes Float32
/// frames into the provided ``RingBuffer``.
public final class MicrophoneCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let buffer: RingBuffer

    public init(buffer: RingBuffer) { self.buffer = buffer }

    public func start() throws {
        let input = engine.inputNode
        let format = AVAudioFormat(
            standardFormatWithSampleRate: CanonicalAudioFormat.sampleRate,
            channels: CanonicalAudioFormat.channelCount)!
        input.installTap(onBus: 0, bufferSize: 1024, format: format) {
            [weak self] pcm, _ in
            guard let self, let chans = pcm.floatChannelData else { return }
            _ = self.buffer.write(chans[0], count: Int(pcm.frameLength))
        }
        engine.prepare()
        try engine.start()
    }

    public func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
```

**Step 2: Implement `VirtualMicClient`** in the app target — an XPC client to
the driver that drains a `RingBuffer` and forwards frames to the driver's
input-stream ring.

**Step 3: Wire the two together** behind a "Test mic → virtual mic" button on
the temporary onboarding screen. Use the button to verify that selecting
"VoiceMiddle Mic" in QuickTime Player → Audio Input shows the live waveform
of your real mic.

**Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(audio): pass microphone audio through to virtual mic device

- MicrophoneCapture taps AVAudioEngine input at 48 kHz / mono / Float32
- VirtualMicClient drains the ring buffer and writes frames to the driver
- Manual verification: QuickTime sees live waveform on VoiceMiddle Mic
EOF
)"
```

---

### Task 1.11: Phase 1 smoke test and milestone tag

**Step 1:** Run through the manual checklist:
* `./scripts/check.sh` — all green.
* Launch the app, install driver, accept system prompt.
* In QuickTime, pick "VoiceMiddle Mic" → speak — waveform visible.
* In Google Meet (no-call self-test): pick "VoiceMiddle Mic" → see meter
  bouncing on local audio test.

**Step 2:** Tag the milestone.

```bash
git tag -a phase-1-skeleton -m "Phase 1 complete: skeleton and pass-through mic"
```

**Step 3:** Commit any leftover docs.

---

## Phase 2 — Inbound pipeline

### Task 2.1: Scribe v2 WebSocket transport

**Files:**
- Create: `Sources/VMScribe/ScribeV2StreamClient.swift`
- Create: `Sources/VMScribe/STTStreamClient.swift` (protocol moved here)
- Create: `Tests/VMScribeTests/ScribeV2StreamClientTests.swift`

**Step 1: Define the `STTStreamClient` protocol** as in the spec §4.4.

**Step 2: Write the failing test** using a local `NWListener` that emulates
Scribe's WebSocket framing:
* Accepts an audio binary frame, replies with a partial JSON, then a final
  JSON after `flushUtterance`.
* Asserts that the client emits the same partials and finals on its
  `AsyncStream`s.

**Step 3: Implement `ScribeV2StreamClient`** with
`URLSessionWebSocketTask`:
* `init(url: URL, apiKey: String, sourceLanguage: LanguageCode)`.
* On `send(_:)`, encode PCM as `Data` and `webSocketTask.send(.data(...))`.
* On `flushUtterance()`, send the JSON sentinel `{"type":"end_of_utterance"}`.
* Continuously read messages, parse the JSON, demultiplex into `partials`
  and `finals` `AsyncStream` continuations.
* Reconnect loop with exponential backoff (250 ms → 4 s).

**Step 4: Run**

`swift test --filter ScribeV2StreamClientTests` → PASS.

**Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(vmscribe): add Scribe v2 realtime WebSocket client

- STTStreamClient protocol with partials/finals AsyncStreams
- ScribeV2StreamClient wraps URLSessionWebSocketTask
- Exponential backoff reconnect, 250 ms → 4 s
- Tested against a local NWListener that emulates Scribe framing
EOF
)"
```

---

### Task 2.2: Translator protocol and Claude implementation

**Files:**
- Create: `Sources/VMTranslators/Translator.swift`
- Create: `Sources/VMTranslators/TranslatorID.swift`
- Create: `Sources/VMTranslators/ClaudeTranslator.swift`
- Create: `Tests/VMTranslatorsTests/ClaudeTranslatorTests.swift`

**Step 1: Test** using `URLProtocol` injection so the test never hits the
network. Assert that:
* The request body matches the Anthropic Messages API schema.
* Conversation context is rendered into a single user message block.
* The system prompt is constant and marked with `cache_control: {type:
  "ephemeral"}`.
* The response's `content[0].text` is returned verbatim.

**Step 2: Implement** `ClaudeTranslator`:
```swift
public final class ClaudeTranslator: Translator {
    public let identifier: TranslatorID = .claudeHaiku45
    public let supportsContext = true

    private let session: URLSession
    private let apiKey: String
    private let model: String
    private let endpoint: URL

    public init(apiKey: String, session: URLSession = .shared,
                model: String = "claude-haiku-4-5-20251001",
                endpoint: URL = URL(
                    string: "https://api.anthropic.com/v1/messages")!) {
        self.apiKey = apiKey
        self.session = session
        self.model = model
        self.endpoint = endpoint
    }

    public func translate(
        _ text: String,
        from source: LanguageCode,
        to target: LanguageCode,
        context: ConversationContext?
    ) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json",
                         forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01",
                         forHTTPHeaderField: "anthropic-version")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

        let body = MessagesRequestBody(
            model: model,
            system: Self.systemPrompt(source: source, target: target),
            messages: Self.messages(text: text, context: context),
            maxTokens: 1024,
            temperature: 0
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw TranslationError.upstream(statusCode:
                (response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        let decoded = try JSONDecoder().decode(
            MessagesResponseBody.self, from: data)
        guard let translated = decoded.content.first?.text else {
            throw TranslationError.emptyResponse
        }
        return translated.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // ... `systemPrompt`, `messages`, request/response Codable types
}
```

System prompt: a short paragraph that instructs Claude to translate
verbatim, preserve register, never add commentary, and use the recent
turns as context only.

**Step 3: Run** test → PASS.

**Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(translators): add Translator protocol and ClaudeTranslator

- Pluggable Translator protocol with supportsContext flag
- ClaudeTranslator hits Anthropic Messages API via URLSession
- System prompt marked ephemeral for prompt caching
- Conversation context rendered as a single structured user message
- URLProtocol-injected tests assert request/response contract
EOF
)"
```

---

### Task 2.3: GPT translator implementation

Same structure as 2.2. `Sources/VMTranslators/GPTTranslator.swift`. POST to
`https://api.openai.com/v1/chat/completions` with `messages[]` carrying the
conversation context as `{role: "user"|"assistant", content: ...}`. Test with
canned JSON via `URLProtocol`. Commit:

```
feat(translators): add GPTTranslator using OpenAI Chat Completions API
```

---

### Task 2.4: DeepL translator implementation

`Sources/VMTranslators/DeepLTranslator.swift`. POST to
`https://api.deepl.com/v2/translate` (or `api-free` if free-tier key). `supportsContext = false`. No
`ConversationContext` payload. Test with canned JSON. Commit:

```
feat(translators): add DeepLTranslator with REST API integration
```

---

### Task 2.5: Translator contract test suite

**Files:**
- Create: `Tests/VMTranslatorsTests/TranslatorContractTests.swift`

A shared `Suite` parameterized over translator implementations (with mocked
URL responses) that asserts:
* Round-trip of a known phrase returns the canned translation.
* Empty source string throws `TranslationError.emptySource`.
* Upstream 5xx throws `TranslationError.upstream`.

This is the @superpowers:test-driven-development pattern: write the suite
once, run against each implementation.

Commit: `test(translators): add shared contract suite across all translators`.

---

### Task 2.6: Flash v2.5 WebSocket TTS client

**Files:**
- Create: `Sources/VMFlash/TTSStreamClient.swift`
- Create: `Sources/VMFlash/FlashV2StreamClient.swift`
- Create: `Tests/VMFlashTests/FlashV2StreamClientTests.swift`

Same pattern as 2.1 but for outgoing WebSocket. Connect to
`wss://api.elevenlabs.io/v1/text-to-speech/{voice_id}/stream-input`. Send
JSON `{"text": "...", "flush": true}` and receive base64-encoded PCM chunks.
The `sink` is called for each decoded chunk. Test against a local
WebSocket echo server that returns canned audio.

Commit: `feat(vmflash): add Flash v2.5 streaming TTS WebSocket client`.

---

### Task 2.7: Voice activity detector

**Files:**
- Create: `Sources/VMPipeline/VAD.swift`
- Create: `Tests/VMPipelineTests/VADTests.swift`

Implement a simple energy + zero-crossing-rate VAD as a value type:
```swift
public struct VAD: Sendable {
    public init(sampleRate: Double = 48_000,
                energyThreshold: Float = 0.005,
                zcrThreshold: Float = 0.1,
                hangoverMs: Int = 600) { … }

    /// Returns a state transition for a 10 ms frame of audio.
    public mutating func process(frame: UnsafeBufferPointer<Float>) -> Event
    public enum Event { case continued, speechStarted, speechEnded }
}
```

Tests feed synthetic frames (silence, sine wave bursts) and assert on the
emitted events.

Commit: `feat(vmpipeline): add energy/ZCR voice activity detector`.

---

### Task 2.8: Audio chunker

**Files:**
- Create: `Sources/VMPipeline/AudioChunker.swift`
- Create: `Tests/VMPipelineTests/AudioChunkerTests.swift`

Wraps a `RingBuffer` consumer and a `VAD`, exposes:
```swift
public struct AudioChunker: Sendable {
    public init(input: RingBuffer, vad: VAD)
    public var utterances: AsyncStream<[Float]> { get }   // one per utterance
}
```

Reads in 10 ms frames, accumulates until `speechEnded`, then emits the
buffered utterance. Tests feed canned PCM and assert on the number and
length of emitted utterances.

Commit: `feat(vmpipeline): add AudioChunker driven by VAD over a RingBuffer`.

---

### Task 2.9: Transcript aggregator

**Files:**
- Create: `Sources/VMPipeline/TranscriptAggregator.swift`
- Create: `Tests/VMPipelineTests/TranscriptAggregatorTests.swift`

Accepts partial and final transcripts from an `STTStreamClient` and emits
"flushable utterances" depending on the configured `PaceMode`:
* `.turnBased`: emit on each `final` only.
* `.streaming`: emit on partial when it contains a clause boundary
  (`,`, `;`, end-of-thought heuristic) or after `1200 ms` of unflushed
  text, whichever comes first.

Tests are deterministic by injecting a clock and feeding scripted partials.

Commit: `feat(vmpipeline): add TranscriptAggregator with turn and streaming modes`.

---

### Task 2.10: Translation pipeline

**Files:**
- Create: `Sources/VMPipeline/TranslationPipeline.swift`
- Create: `Tests/VMPipelineTests/TranslationPipelineTests.swift`

The orchestrator. Takes injected dependencies (STT, translator, TTS,
audio chunker, context actor, settings, sinks) and exposes:

```swift
public actor TranslationPipeline {
    public init(direction: Direction,
                source: LanguageCode,
                target: LanguageCode,
                voice: VoiceID,
                stt: any STTStreamClient,
                translator: any Translator,
                tts: any TTSStreamClient,
                chunker: AudioChunker,
                context: ConversationContextActor,
                audioSink: any AudioSink,
                transcriptSink: any TranscriptSink,
                settings: SettingsStore)
    public func start() async
    public func stop() async
}
```

Internally runs three structured tasks:
1. Consume `chunker.utterances`, push PCM into `stt`, call `flushUtterance`
   on `endOfUtterance`.
2. Consume `aggregator.flushable`, call `translator.translate`, then
   `tts.synthesize`.
3. Consume `tts` chunks, write to `audioSink`.

Tests use in-memory fakes for STT, Translator, TTS, sinks, and feed canned
audio. Assert the expected sequence of events on the sinks.

Commit: `feat(vmpipeline): add TranslationPipeline orchestrator with structured tasks`.

---

### Task 2.11: App audio capture via Core Audio Process Taps

**Files:**
- Create: `Sources/VMAudio/AppAudioCapture.swift`
- Create: `Sources/VMAudio/AudioProcess.swift`
- Create: `Tests/VMAudioTests/AppAudioCaptureTests.swift` (smoke)

`AudioProcess` enumerates audio-producing processes via
`kAudioHardwarePropertyProcessObjectList` and exposes
`{pid, bundleID, displayName, isProducingAudio}`. Tests assert the type
shape with a fixture array (no live enumeration in CI).

`AppAudioCapture` creates a `CATapDescription` in `.processMix` mode,
calls `AudioHardwareCreateProcessTap` and
`AudioHardwareCreateAggregateDevice`, then opens the aggregate device with
an `AudioDeviceIOProc` that writes 48 kHz mono Float32 into the provided
`RingBuffer`.

Manual verification: tap Google Chrome while it plays a YouTube video and
ensure `RingBuffer.approximateCount > 0`. No automated test.

Commit: `feat(vmaudio): add AppAudioCapture using Core Audio Process Taps`.

---

### Task 2.12: Headphone output engine with ducking

**Files:**
- Create: `Sources/VMAudio/OutputEngine.swift`
- Create: `Tests/VMAudioTests/OutputEngineTests.swift`

`OutputEngine` owns an `AVAudioEngine` with:
* An `AVAudioPlayerNode` for the inbound original (fed by `AppAudioCapture`).
* An `AVAudioPlayerNode` for the inbound TTS (fed by Flash).
* An `AVAudioMixerNode` mixing both, with the original's gain controlled
  by a smoothed ramp.
* Methods `duckOriginal(to dB: Float, fadeMs: Int)` and
  `restoreOriginal(fadeMs: Int)`.

Tests assert ramp math (apply ramp to a synthetic sample stream and check
expected dB at midpoint). Manual verification with real audio.

Commit: `feat(vmaudio): add OutputEngine with ducked mix of original and TTS`.

---

### Task 2.13: Wire Phase 2 end-to-end behind a debug toggle

**Files:**
- Modify: `VoiceMiddle/App/SessionController.swift`
- Create: `VoiceMiddle/App/InboundDemoView.swift`

Add a temporary "Inbound demo" view in Settings that lets the user:
* Pick a target process from `AudioProcess.enumerate()`.
* Pick source/target languages and a voice.
* Enter API keys (Anthropic + ElevenLabs).
* Start/stop a single-direction inbound pipeline.

This is throwaway UI replaced in Phase 4 by the real Settings tabs. The
goal is the demo milestone: hear a YouTube video translated.

Commit: `feat(app): add temporary inbound demo view for end-to-end testing`.

---

### Task 2.14: Phase 2 milestone tag

Same shape as Task 1.11. Manual checklist:
* Play a 30-second English clip on YouTube.
* Confirm transcript appears within ~700 ms of utterance end.
* Confirm Spanish TTS plays within ~1.5 s of utterance end.
* Confirm YouTube audio ducks while TTS plays.

```bash
git tag -a phase-2-inbound -m "Phase 2 complete: inbound translation pipeline"
```

---

## Phase 3 — Outbound pipeline and HUD

### Task 3.1: Driver real ring buffer and XPC stream

Implement the driver-side ring buffer and XPC user client (replacing the
silent stub from Phase 1). The app pushes Float32 frames over XPC; the
driver writes to its input stream ring served to consumers.

Tests: a small command-line `swift run vmdriverctl` tool that opens the
driver as an input device, plays a sine wave from the app side, and
asserts the consumer reads back the sine wave.

Commit: `feat(driver): add real XPC stream from app into virtual mic ring`.

---

### Task 3.2: Outbound translation pipeline

Wire `MicrophoneCapture` → `AudioChunker` → `TranslationPipeline` (with
direction `.outbound`) → driver ring buffer. Reuse the `TranslationPipeline`
from 2.10 with different sinks.

Manual verification: speak in Spanish on a Google Meet call to a friend,
confirm they hear your English translation.

Commit: `feat(app): wire outbound pipeline from mic to virtual mic`.

---

### Task 3.3: Conversation context wired across pipelines

Both pipelines now share a single `ConversationContextActor`. Each
successful translation calls `appendTurn`. Verify by reading two-sided
transcripts in the HUD and confirming the translator's quality improves
on pronoun ambiguity.

Commit: `feat(vmpipeline): share ConversationContextActor across both pipelines`.

---

### Task 3.4: HUD window

**Files:**
- Create: `VoiceMiddle/HUD/HUDWindowController.swift`
- Create: `VoiceMiddle/HUD/HUDView.swift`
- Create: `VoiceMiddle/HUD/HUDViewModel.swift`

`NSPanel` with `.floating` level, `canBecomeKey = false`, semi-transparent
backdrop, draggable. SwiftUI view listing the most recent N turns from both
pipelines.

`HUDViewModel` is `@MainActor`-isolated, subscribes to a merged
`AsyncStream` of `TranscriptEvent`s emitted by both pipelines.

Manual verification: HUD visible during a call, scrolls as turns flow.

Commit: `feat(hud): add floating HUD window with live two-sided transcript`.

---

### Task 3.5: Read-only inbound mode

Add a checkbox in Settings: "Read transcript only — don't synthesize my
inbound TTS". When true, the inbound `TranslationPipeline` skips the TTS
step.

Implement by injecting an optional `TTSStreamClient` into the inbound
pipeline only — `nil` means transcript-only.

Tests: `TranslationPipeline` test asserts that no audio is written to the
sink in read-only mode but transcript events still flow.

Commit: `feat(vmpipeline): add read-only inbound mode that skips TTS`.

---

### Task 3.6: Onboarding wizard

**Files:**
- Create: `VoiceMiddle/Onboarding/OnboardingView.swift` and supporting steps.

Three-step SwiftUI wizard:
1. Permissions: mic, audio capture, system extension install.
2. API keys: ElevenLabs + one translator. "Test connection" buttons.
3. Pick a target app.

Persist completion flag in `SettingsStore` to skip on subsequent launches.

Commit: `feat(onboarding): add first-launch onboarding wizard with three steps`.

---

### Task 3.7: Phase 3 milestone tag

Manual end-to-end test with two real people on a Google Meet call. Tag:

```bash
git tag -a phase-3-bidi -m "Phase 3 complete: bidirectional translation + HUD"
```

---

## Phase 4 — Configurability and polish

### Task 4.1: Settings window — General tab

`VoiceMiddle/Settings/GeneralTab.swift`. Open at login, show HUD on session
start, HUD opacity, global hotkey rebinder, accent color.

Global hotkey via `CGEventTap` (requires Accessibility permission) wrapped
in an `actor` that re-registers on settings change.

Commit: `feat(settings): add General tab with hotkey rebinder and launch options`.

---

### Task 4.2: Settings window — Languages tab

Source/target language pickers (BCP-47 from a curated list), swap button,
voice preset picker per direction with a "Preview" button that synthesizes
"Hello, world." in the target language using the selected voice.

Commit: `feat(settings): add Languages tab with voice preset preview`.

---

### Task 4.3: Settings window — Translation tab

Translator engine picker (Claude / GPT / DeepL), model selector when
applicable, pace mode picker per direction, API key fields backed by
Keychain.

Commit: `feat(settings): add Translation tab with engine, model, and key fields`.

---

### Task 4.4: Settings window — Audio tab

Target app picker (live `AudioProcess.enumerate()`), input/output device
pickers, VAD sensitivity sliders per direction, ducking mode picker,
ducking level slider (−40 dB to 0 dB), fade duration slider.

Commit: `feat(settings): add Audio tab with target app, devices, VAD, ducking`.

---

### Task 4.5: Settings window — Privacy tab

Transcript persistence toggle, open transcripts directory, clear all
transcripts button, deep links to system permission panes.

Commit: `feat(settings): add Privacy tab with transcript controls`.

---

### Task 4.6: Streaming pace mode end-to-end test

With Task 2.9 already implementing the aggregator's streaming logic, the
final piece is verifying the perceived latency in real conditions. Add a
hidden Diagnostics flag to log per-stage latency. Tune the clause-boundary
heuristic if needed.

Commit: `perf(vmpipeline): tune streaming clause boundaries for sub-1s latency`.

---

### Task 4.7: Ducking configurability

With `OutputEngine` already parameterized in 2.12, surface all three modes
(off / duck / mute) in the Audio tab. Ensure the fade math handles the
"mute" edge case without crackle.

Commit: `feat(vmaudio): support all three ducking modes from settings`.

---

### Task 4.8: Transcript persistence

When the user enables "Save transcripts" in the Privacy tab, write per-turn
JSON to `~/Library/Application Support/VoiceMiddle/Transcripts/<sessionID>.json`.

Tests with a temporary directory; assert one JSON object per turn, ordered.

Commit: `feat(transcripts): persist per-turn JSON when enabled in settings`.

---

### Task 4.9: Phase 4 milestone tag

```bash
git tag -a phase-4-polish -m "Phase 4 complete: full Settings UI, all modes"
```

---

## Phase 5 — Diagnostics, packaging, release

### Task 5.1: PipelineMetrics

`Sources/VMPipeline/PipelineMetrics.swift`: per-pipeline counters and EMA
timings (STT round-trip, translator latency, TTS time-to-first-chunk,
end-to-end). Updated from pipeline tasks via `@MainActor`-isolated calls
or an `actor` wrapping the metrics.

Tests assert that timings update correctly under synthetic load.

Commit: `feat(vmpipeline): add PipelineMetrics counters and EMA timings`.

---

### Task 5.2: Diagnostics window

Hidden ⌥⌘D shortcut opens a SwiftUI window listing live metrics, recent
errors, and a "Copy log range" button that grabs the last N seconds of
`os.Logger` output via the `OSLogStore` API.

Commit: `feat(app): add hidden Diagnostics window with metrics and log export`.

---

### Task 5.3: Notarization and DMG packaging

Add `scripts/release.sh` that:
* Increments build number.
* Archives the app with `xcodebuild archive`.
* Exports a notarized `.app` with `xcodebuild -exportArchive`.
* Builds a signed DMG with `create-dmg`.
* Verifies the DMG passes `spctl --assess`.

Commit: `chore(release): add notarized DMG packaging script`.

---

### Task 5.4: Crash reporting

Integrate a self-hosted KSCrash or `MetricKit` for crash reports (no
third-party SaaS in MVP for privacy). Display a "Send crash report" prompt
on next launch.

Commit: `feat(app): add MetricKit-based crash reporting with opt-in upload`.

---

### Task 5.5: Manual release test matrix

Run the manual test plan from spec §9 on each communication app: Teams,
Meet, Slack, Zoom, FaceTime, Discord. Record results in
`docs/release-checklist-2026-05-11.md`.

Commit: `docs(release): add 2026-05-11 release checklist results`.

---

### Task 5.6: Release tag

```bash
git tag -a v1.0.0 -m "VoiceMiddle 1.0 — initial public release"
```

---

## Cross-cutting reminders for the executor

* Before each task: run `./scripts/check.sh` to ensure the current state is
  green. Never start a new task on a broken tree.
* Each task starts with a failing test (where applicable). Only after the
  red is observed do you write the implementation.
* Commits use the project's conventional format (see
  `/Users/luismo/.claude/rules/commits.md`): no `Co-Authored-By`, no
  `--gpg-sign`, conventional `type(scope): subject` + bulleted body.
* When a task explicitly says "manual verification", do not claim the task
  is done without performing the check — write the result in the commit
  body if it would help review.
* For any task that requires entitlements changes (DriverKit, Accessibility,
  etc.), bump the app version and re-notarize before merging to `main`.

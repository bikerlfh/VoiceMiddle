import AppKit
import AVFoundation
import Combine
import Foundation
import VMAudio
import VMCore
import VMFlash
import VMPipeline
import VMScribe
import VMTranslators

/// Owns the live translation pipelines (inbound and, optionally, outbound)
/// driven entirely from ``SettingsStore``. The driver is `@MainActor` so its
/// published state can back SwiftUI views without bridging hops.
///
/// Responsibilities:
/// - Enumerate available audio processes (filtered to those with a bundle
///   ID) and let callers drive the picker.
/// - Validate that all required environment-variable API keys are present
///   for the configured translator before allowing a Start.
/// - Build the inbound chain (Core Audio Process Tap → STT → translator →
///   TTS → ``OutputEngine``).
/// - When `settings.outboundEnabled` is `true` and the configured Core Audio
///   output device is found, build the outbound chain (microphone capture →
///   STT in the user's language → translator → TTS → ``DeviceOutputSink``
///   targeting the virtual device, e.g. `BlackHole 2ch`).
/// - Drain both pipelines' transcript streams into ``transcript``, the HUD,
///   and the optional ``TranscriptWriter``.
@MainActor
final class SessionDriver: ObservableObject {
    enum State: Hashable {
        case idle
        case running
        case error(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var transcript: [TranscriptEvent] = []
    @Published private(set) var recentErrors: [TranscriptEvent] = []
    @Published var availableProcesses: [AudioProcess] = []
    /// Live snapshot of the outbound output device matched by the configured
    /// name. `nil` when no device matches (e.g. BlackHole isn't installed).
    @Published private(set) var outboundDeviceStatus: OutputDevice?
    /// EMA RMS level of the most-recently-captured target-app audio, in
    /// `[0, 1]`. Updated at ~30 Hz while a session is running; 0 otherwise.
    @Published private(set) var inboundLevel: Float = 0
    /// EMA RMS level of the most-recently-captured microphone audio, in
    /// `[0, 1]`. Updated at ~30 Hz while a session is running with outbound
    /// enabled; 0 otherwise.
    @Published private(set) var outboundLevel: Float = 0

    private static let maxRecentErrors = 20

    private let settings: SettingsStore
    private let hudViewModel: HUDViewModel?
    private let metrics: PipelineMetrics?
    private var inboundPipeline: TranslationPipeline?
    private var outboundPipeline: TranslationPipeline?
    private var capture: AppAudioCapture?
    private var micCapture: MicrophoneCapture?
    private var outputEngine: OutputEngine?
    private var deviceSink: DeviceOutputSink?
    private var inboundObserver: Task<Void, Never>?
    private var outboundObserver: Task<Void, Never>?
    private var transcriptWriter: TranscriptWriter?
    private var inboundBuffer: RingBuffer?
    private var outboundBuffer: RingBuffer?
    private var levelPollingTask: Task<Void, Never>?

    init(
        settings: SettingsStore,
        hudViewModel: HUDViewModel? = nil,
        metrics: PipelineMetrics? = nil
    ) {
        self.settings = settings
        self.hudViewModel = hudViewModel
        self.metrics = metrics
        refreshProcesses()
        refreshOutboundDevice()
    }

    // MARK: - Process discovery

    func refreshProcesses() {
        availableProcesses = AudioProcess.enumerate()
            .filter { $0.bundleID != nil }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name)
                    == .orderedAscending
            }
    }

    /// Re-runs Core Audio device enumeration and updates
    /// ``outboundDeviceStatus``.
    func refreshOutboundDevice() {
        outboundDeviceStatus = OutputDevice.firstMatching(
            name: settings.outboundDeviceName
        )
    }

    // MARK: - Preconditions

    /// True when the driver is idle and the env-var keys required by the
    /// currently selected translator are all populated.
    func canStart() -> Bool {
        guard state == .idle else { return false }
        let env = ProcessInfo.processInfo.environment
        guard !(env["ELEVENLABS_API_KEY"] ?? "").isEmpty else {
            return false
        }
        switch settings.translatorIdentifier {
        case "deepL":
            return !(env["DEEPL_API_KEY"] ?? "").isEmpty
        case "claudeHaiku45":
            return !(env["ANTHROPIC_API_KEY"] ?? "").isEmpty
        case "gpt4oMini":
            return !(env["OPENAI_API_KEY"] ?? "").isEmpty
        default:
            return false
        }
    }

    // MARK: - Lifecycle

    func start() async {
        guard state == .idle else { return }
        transcript.removeAll(keepingCapacity: true)
        do {
            let wiring = try await bringUp()
            self.inboundPipeline = wiring.inbound
            self.outboundPipeline = wiring.outbound

            inboundObserver = observe(pipeline: wiring.inbound)
            if let outbound = wiring.outbound {
                outboundObserver = observe(pipeline: outbound)
            }

            await wiring.inbound.start()
            await wiring.outbound?.start()
            startLevelPolling()
            state = .running
        } catch {
            await tearDown()
            state = .error(error.localizedDescription)
        }
    }

    func stop() async {
        inboundObserver?.cancel()
        outboundObserver?.cancel()
        inboundObserver = nil
        outboundObserver = nil
        levelPollingTask?.cancel()
        levelPollingTask = nil
        await tearDown()
        inboundLevel = 0
        outboundLevel = 0
        state = .idle
    }

    private func startLevelPolling() {
        levelPollingTask?.cancel()
        levelPollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.inboundLevel = self.inboundBuffer?.currentLevel ?? 0
                self.outboundLevel = self.outboundBuffer?.currentLevel ?? 0
                try? await Task.sleep(nanoseconds: 33_000_000)   // ~30 Hz
            }
        }
    }

    // MARK: - Wiring

    private func observe(
        pipeline: TranslationPipeline
    ) -> Task<Void, Never> {
        let stream = pipeline.transcript
        return Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                self.transcript.append(event)
                self.hudViewModel?.accept(event)
                self.transcriptWriter?.append(event)
                if case .error = event {
                    self.recentErrors.append(event)
                    if self.recentErrors.count > Self.maxRecentErrors {
                        self.recentErrors.removeFirst(
                            self.recentErrors.count
                                - Self.maxRecentErrors
                        )
                    }
                }
            }
        }
    }

    private func tearDown() async {
        if let inboundPipeline {
            await inboundPipeline.stop()
        }
        inboundPipeline = nil
        if let outboundPipeline {
            await outboundPipeline.stop()
        }
        outboundPipeline = nil
        if let capture {
            await capture.stop()
        }
        capture = nil
        if let micCapture {
            micCapture.stop()
        }
        micCapture = nil
        if let outputEngine {
            await outputEngine.stop()
        }
        outputEngine = nil
        if let deviceSink {
            await deviceSink.stop()
        }
        deviceSink = nil
        transcriptWriter?.close()
        transcriptWriter = nil
        inboundBuffer = nil
        outboundBuffer = nil
    }

    private struct Wiring {
        let inbound: TranslationPipeline
        let outbound: TranslationPipeline?
    }

    private func bringUp() async throws -> Wiring {
        let env = ProcessInfo.processInfo.environment
        let source = try LanguageCode(settings.sourceLanguageCode)
        let target = try LanguageCode(settings.targetLanguageCode)
        let voice = VoiceID(settings.voiceID)

        guard let bundleID = settings.selectedTargetBundleID,
              let process = availableProcesses.first(
                where: { $0.bundleID == bundleID }
              )
        else {
            throw NSError(
                domain: "VoiceMiddle.SessionDriver",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: "No target app selected.",
                ]
            )
        }

        // 4 s @ 48 kHz mono of buffering between capture and chunker, so a
        // momentarily-stalled consumer doesn't immediately drop audio.
        let inboundBuffer = RingBuffer(capacity: 48_000 * 4)
        self.inboundBuffer = inboundBuffer
        let capture = AppAudioCapture(
            process: process, buffer: inboundBuffer
        )
        try await capture.start()
        self.capture = capture

        let inboundSensitivity = settings.vadSensitivity(for: .inbound)
        let inboundVAD = VAD(energyThreshold: inboundSensitivity)
        let inboundChunker = AudioChunker(
            input: inboundBuffer, vad: inboundVAD
        )

        let elevenLabsKey = env["ELEVENLABS_API_KEY"] ?? ""
        let inboundSTT = ScribeV2StreamClient(
            url: URL(string:
                "wss://api.elevenlabs.io/v1/speech-to-text/realtime"
            )!,
            apiKey: elevenLabsKey,
            sourceLanguage: source
        )

        let translator = makeTranslator(env: env)

        let inboundTTS: (any TTSStreamClient)? = settings.readOnlyInbound
            ? nil
            : FlashV2StreamClient(apiKey: elevenLabsKey)

        let inboundAggregator = TranscriptAggregator(
            mode: settings.paceMode(for: .inbound)
        )
        let context = ConversationContextActor()

        let outputEngine = OutputEngine(
            duckingMode: settings.duckingMode,
            duckingLevelDB: settings.duckingLevelDB,
            fadeMs: settings.duckingFadeMs
        )
        try await outputEngine.start()
        self.outputEngine = outputEngine

        if settings.saveTranscripts {
            let writer = TranscriptWriter()
            try writer.start()
            transcriptWriter = writer
        }

        let inbound = TranslationPipeline(
            direction: .inbound,
            source: source,
            target: target,
            voice: voice,
            stt: inboundSTT,
            translator: translator,
            tts: inboundTTS,
            chunker: inboundChunker,
            aggregator: inboundAggregator,
            context: context,
            audioSink: outputEngine,
            metrics: metrics
        )

        let outbound = try await buildOutbound(
            env: env,
            elevenLabsKey: elevenLabsKey,
            translator: translator,
            context: context,
            voice: voice,
            source: source,
            target: target
        )

        return Wiring(inbound: inbound, outbound: outbound)
    }

    private func buildOutbound(
        env: [String: String],
        elevenLabsKey: String,
        translator: any Translator,
        context: ConversationContextActor,
        voice: VoiceID,
        source: LanguageCode,
        target: LanguageCode
    ) async throws -> TranslationPipeline? {
        guard settings.outboundEnabled else { return nil }
        guard let device = OutputDevice.firstMatching(
            name: settings.outboundDeviceName
        ) else {
            outboundDeviceStatus = nil
            return nil
        }
        outboundDeviceStatus = device

        let micBuffer = RingBuffer(capacity: 48_000 * 4)
        self.outboundBuffer = micBuffer
        let micCapture = MicrophoneCapture(buffer: micBuffer)
        try micCapture.start()
        self.micCapture = micCapture

        let outboundVAD = VAD(
            energyThreshold: settings.vadSensitivity(for: .outbound)
        )
        let outboundChunker = AudioChunker(
            input: micBuffer, vad: outboundVAD
        )

        // For outbound, the source language is the user's language (= the
        // inbound's target) and the target language is the remote party's
        // language (= the inbound's source). The translator carries the user
        // voice across so the other party hears their language.
        let outboundSTT = ScribeV2StreamClient(
            url: URL(string:
                "wss://api.elevenlabs.io/v1/speech-to-text/realtime"
            )!,
            apiKey: elevenLabsKey,
            sourceLanguage: target
        )
        let outboundTTS: any TTSStreamClient = FlashV2StreamClient(
            apiKey: elevenLabsKey
        )
        let outboundAggregator = TranscriptAggregator(
            mode: settings.paceMode(for: .outbound)
        )

        let sink = DeviceOutputSink()
        try await sink.start(deviceID: device.id)
        self.deviceSink = sink

        return TranslationPipeline(
            direction: .outbound,
            source: target,
            target: source,
            voice: voice,
            stt: outboundSTT,
            translator: translator,
            tts: outboundTTS,
            chunker: outboundChunker,
            aggregator: outboundAggregator,
            context: context,
            audioSink: sink,
            metrics: metrics
        )
    }

    private func makeTranslator(env: [String: String]) -> any Translator {
        switch settings.translatorIdentifier {
        case "claudeHaiku45":
            return ClaudeTranslator(
                apiKey: env["ANTHROPIC_API_KEY"] ?? "",
                model: settings.claudeModel
            )
        case "gpt4oMini":
            return GPTTranslator(
                apiKey: env["OPENAI_API_KEY"] ?? "",
                model: settings.openAIModel
            )
        default:
            let deepLKey = env["DEEPL_API_KEY"] ?? ""
            let endpoint: URL = deepLKey.hasSuffix(":fx")
                ? URL(string:
                    "https://api-free.deepl.com/v2/translate")!
                : URL(string:
                    "https://api.deepl.com/v2/translate")!
            return DeepLTranslator(
                apiKey: deepLKey, endpoint: endpoint
            )
        }
    }
}

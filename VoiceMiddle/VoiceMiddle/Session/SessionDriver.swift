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

/// Owns a live inbound translation pipeline driven entirely from
/// ``SettingsStore``. The driver is `@MainActor` so its published state can
/// back SwiftUI views without bridging hops.
///
/// Responsibilities:
/// - Enumerate available audio processes (filtered to those with a bundle
///   ID) and let callers drive the picker.
/// - Validate that all required environment-variable API keys are present
///   for the configured translator before allowing a Start.
/// - Build the audio capture + STT + translator + (optional) TTS chain and
///   drain the pipeline's transcript stream into ``transcript``, the HUD,
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

    private static let maxRecentErrors = 20

    private let settings: SettingsStore
    private let hudViewModel: HUDViewModel?
    private let metrics: PipelineMetrics?
    private var pipeline: TranslationPipeline?
    private var capture: AppAudioCapture?
    private var outputEngine: OutputEngine?
    private var observer: Task<Void, Never>?
    private var transcriptWriter: TranscriptWriter?

    init(
        settings: SettingsStore,
        hudViewModel: HUDViewModel? = nil,
        metrics: PipelineMetrics? = nil
    ) {
        self.settings = settings
        self.hudViewModel = hudViewModel
        self.metrics = metrics
        refreshProcesses()
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
            let pipeline = try await bringUp()
            self.pipeline = pipeline
            let stream = pipeline.transcript
            observer = Task { [weak self] in
                for await event in stream {
                    guard let self else { return }
                    self.transcript.append(event)
                    self.hudViewModel?.accept(event)
                    self.transcriptWriter?.append(event)
                    if case .error = event {
                        self.recentErrors.append(event)
                        if self.recentErrors.count
                            > Self.maxRecentErrors
                        {
                            self.recentErrors.removeFirst(
                                self.recentErrors.count
                                    - Self.maxRecentErrors
                            )
                        }
                    }
                }
            }
            await pipeline.start()
            state = .running
        } catch {
            await tearDown()
            state = .error(error.localizedDescription)
        }
    }

    func stop() async {
        observer?.cancel()
        observer = nil
        await tearDown()
        state = .idle
    }

    // MARK: - Wiring

    private func tearDown() async {
        if let pipeline {
            await pipeline.stop()
        }
        pipeline = nil
        if let capture {
            await capture.stop()
        }
        capture = nil
        if let outputEngine {
            await outputEngine.stop()
        }
        outputEngine = nil
        transcriptWriter?.close()
        transcriptWriter = nil
    }

    private func bringUp() async throws -> TranslationPipeline {
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
        let ringBuffer = RingBuffer(capacity: 48_000 * 4)
        let capture = AppAudioCapture(
            process: process, buffer: ringBuffer
        )
        try await capture.start()
        self.capture = capture

        let inboundSensitivity = settings.vadSensitivity(for: .inbound)
        let vad = VAD(energyThreshold: inboundSensitivity)
        let chunker = AudioChunker(input: ringBuffer, vad: vad)

        let elevenLabsKey = env["ELEVENLABS_API_KEY"] ?? ""
        let scribe = ScribeV2StreamClient(
            url: URL(string:
                "wss://api.elevenlabs.io/v1/speech-to-text/realtime"
            )!,
            apiKey: elevenLabsKey,
            sourceLanguage: source
        )

        let translator: any Translator
        switch settings.translatorIdentifier {
        case "claudeHaiku45":
            translator = ClaudeTranslator(
                apiKey: env["ANTHROPIC_API_KEY"] ?? "",
                model: settings.claudeModel
            )
        case "gpt4oMini":
            translator = GPTTranslator(
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
            translator = DeepLTranslator(
                apiKey: deepLKey, endpoint: endpoint
            )
        }

        let tts: (any TTSStreamClient)? = settings.readOnlyInbound
            ? nil
            : FlashV2StreamClient(apiKey: elevenLabsKey)

        let aggregator = TranscriptAggregator(
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

        return TranslationPipeline(
            direction: .inbound,
            source: source,
            target: target,
            voice: voice,
            stt: scribe,
            translator: translator,
            tts: tts,
            chunker: chunker,
            aggregator: aggregator,
            context: context,
            audioSink: outputEngine,
            metrics: metrics
        )
    }
}

import Combine
import Foundation
import SwiftUI
import VMAudio
import VMCore
import VMFlash
import VMPipeline
import VMScribe
import VMTranslators

/// View model for ``InboundDemoView`` — the Task 2.13 end-to-end demo
/// scene. Owns one ``TranslationPipeline`` and its dependencies, surfaces
/// the rolling transcript to the view, and validates the demo's
/// preconditions (env-var API keys).
@MainActor
final class InboundDemoViewModel: ObservableObject {
    enum RunState: Equatable {
        case idle
        case starting
        case running
        case stopping
    }

    // MARK: - Inputs

    @Published var availableProcesses: [AudioProcess] = []
    @Published var selectedProcess: AudioProcess?
    @Published var sourceLanguage: String = "en"
    @Published var targetLanguage: String = "es"
    @Published var voiceID: String = "21m00Tcm4TlvDq8ikWAM"
    @Published var readOnlyInbound: Bool {
        didSet {
            settings.readOnlyInbound = readOnlyInbound
        }
    }

    // MARK: - Status

    @Published private(set) var runState: RunState = .idle
    @Published private(set) var lastError: String?
    @Published private(set) var transcript: [TranscriptDisplayEvent] = []

    let elevenLabsKeyAvailable: Bool
    let deepLKeyAvailable: Bool

    /// Hard-coded language menu for the demo.
    let supportedLanguages: [String] =
        ["en", "es", "de", "fr", "pt", "it", "ja", "ko"]

    // MARK: - Stored env-derived secrets

    private let elevenLabsKey: String
    private let deepLKey: String
    private let settings: SettingsStore

    // MARK: - Pipeline state

    private var pipeline: TranslationPipeline?
    private var capture: AppAudioCapture?
    private var outputEngine: OutputEngine?
    private var transcriptTask: Task<Void, Never>?
    private weak var hudViewModel: HUDViewModel?

    init(
        hudViewModel: HUDViewModel? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        settings: SettingsStore = SettingsStore()
    ) {
        let elKey = environment["ELEVENLABS_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let dlKey = environment["DEEPL_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.elevenLabsKey = elKey
        self.deepLKey = dlKey
        self.elevenLabsKeyAvailable = !elKey.isEmpty
        self.deepLKeyAvailable = !dlKey.isEmpty
        self.hudViewModel = hudViewModel
        self.settings = settings
        self.readOnlyInbound = settings.readOnlyInbound
        refreshProcesses()
    }

    // MARK: - Process discovery

    func refreshProcesses() {
        let raw = AudioProcess.enumerate()
        let filtered = raw
            .filter { $0.bundleID != nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name)
                == .orderedAscending }
        availableProcesses = filtered
        if let current = selectedProcess,
           !filtered.contains(where: { $0.id == current.id }) {
            selectedProcess = nil
        }
        if selectedProcess == nil {
            selectedProcess = filtered.first
        }
    }

    // MARK: - Start / stop

    var canStart: Bool {
        runState == .idle
            && elevenLabsKeyAvailable
            && deepLKeyAvailable
            && selectedProcess != nil
            && !voiceID.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func start() {
        guard runState == .idle else { return }
        guard elevenLabsKeyAvailable else {
            lastError = "ELEVENLABS_API_KEY is not set."
            return
        }
        guard deepLKeyAvailable else {
            lastError = "DEEPL_API_KEY is not set."
            return
        }
        guard let process = selectedProcess else {
            lastError = "Select a target app first."
            return
        }
        let source: LanguageCode
        let target: LanguageCode
        do {
            source = try LanguageCode(sourceLanguage)
            target = try LanguageCode(targetLanguage)
        } catch {
            lastError = "Invalid language code: \(error)"
            return
        }
        let voice = VoiceID(
            voiceID.trimmingCharacters(in: .whitespaces)
        )
        lastError = nil
        runState = .starting
        transcript.removeAll(keepingCapacity: true)

        Task { @MainActor in
            await self.bringUp(
                process: process,
                source: source,
                target: target,
                voice: voice
            )
        }
    }

    func stop() {
        guard runState == .running || runState == .starting else { return }
        runState = .stopping
        Task { @MainActor in
            await self.tearDown()
            self.runState = .idle
        }
    }

    // MARK: - Private wiring

    private func bringUp(
        process: AudioProcess,
        source: LanguageCode,
        target: LanguageCode,
        voice: VoiceID
    ) async {
        // 1 s @ 48 kHz mono buffering between capture and chunker.
        let ringBuffer = RingBuffer(capacity: 48_000)
        let capture = AppAudioCapture(
            process: process, buffer: ringBuffer
        )
        let chunker = AudioChunker(input: ringBuffer)

        let outputEngine = OutputEngine()
        do {
            try await outputEngine.start()
        } catch {
            lastError = "OutputEngine failed: \(error)"
            runState = .idle
            return
        }

        let stt = ScribeV2StreamClient(
            url: URL(string: "wss://api.elevenlabs.io/v1/speech-to-text/realtime")!,
            apiKey: elevenLabsKey,
            sourceLanguage: source
        )
        let endpoint: URL = elevenLabsURL(forDeepLKey: deepLKey)
        let translator = DeepLTranslator(
            apiKey: deepLKey, endpoint: endpoint
        )
        let flash = FlashV2StreamClient(apiKey: elevenLabsKey)
        let ttsForPipeline: (any TTSStreamClient)? =
            readOnlyInbound ? nil : flash
        let aggregator = TranscriptAggregator(mode: .turnBased)
        let context = ConversationContextActor()

        let pipeline = TranslationPipeline(
            direction: .inbound,
            source: source,
            target: target,
            voice: voice,
            stt: stt,
            translator: translator,
            tts: ttsForPipeline,
            chunker: chunker,
            aggregator: aggregator,
            context: context,
            audioSink: outputEngine,
            topicHint: nil
        )

        do {
            try await capture.start()
        } catch {
            await outputEngine.stop()
            lastError = "AppAudioCapture failed: \(error)"
            runState = .idle
            return
        }
        await pipeline.start()

        self.capture = capture
        self.outputEngine = outputEngine
        self.pipeline = pipeline
        startDrainingTranscript(pipeline: pipeline)
        runState = .running
    }

    private func tearDown() async {
        transcriptTask?.cancel()
        transcriptTask = nil
        if let pipeline {
            await pipeline.stop()
        }
        if let capture {
            await capture.stop()
        }
        if let outputEngine {
            await outputEngine.stop()
        }
        pipeline = nil
        capture = nil
        outputEngine = nil
    }

    private func startDrainingTranscript(pipeline: TranslationPipeline) {
        let stream = pipeline.transcript
        transcriptTask = Task { @MainActor [weak self] in
            for await event in stream {
                guard let self else { return }
                self.appendTranscript(event)
            }
        }
    }

    private func appendTranscript(_ event: TranscriptEvent) {
        let display = TranscriptDisplayEvent(
            id: UUID(), timestamp: Date(), event: event
        )
        transcript.append(display)
        // Cap history to avoid unbounded growth.
        if transcript.count > 200 {
            transcript.removeFirst(transcript.count - 200)
        }
        hudViewModel?.accept(event)
    }

    /// DeepL Free-tier keys end with `:fx` and use the
    /// `api-free.deepl.com` host. Pro keys use `api.deepl.com`.
    private func elevenLabsURL(forDeepLKey key: String) -> URL {
        if key.hasSuffix(":fx") {
            return URL(string: "https://api-free.deepl.com/v2/translate")!
        }
        return URL(string: "https://api.deepl.com/v2/translate")!
    }
}

/// View-layer wrapper that pairs a ``TranscriptEvent`` with the wall-clock
/// time it was observed. The pipeline's `TranscriptEvent` is `Hashable`
/// (and so usable in identity-sensitive list APIs directly), but pairing it
/// with a UUID keeps the list stable across rapid re-renders.
struct TranscriptDisplayEvent: Identifiable, Hashable {
    let id: UUID
    let timestamp: Date
    let event: TranscriptEvent
}

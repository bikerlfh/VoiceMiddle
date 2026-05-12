@preconcurrency import AVFoundation
import Foundation
import VMAudio
import VMCore
import VMFlash
import VMScribe
import VMTranslators

/// Orchestrates the translation flow for a single ``Direction``.
///
/// Wiring:
/// ```
/// AudioChunker.utterances → STT.send + flushUtterance → STT.partials/finals
///                                                            ↓
///                                                  TranscriptAggregator
///                                                            ↓
///                                                  Translator.translate
///                                                            ↓
///                                                    TTS.synthesize → sink
/// ```
///
/// The pipeline does NOT own its dependencies. Callers wire them and pass
/// them in; the pipeline owns the connecting tasks and the broadcast
/// ``transcript`` stream.
///
/// When ``tts`` is `nil` (read-only mode), the pipeline still emits
/// ``TranscriptEvent`` values but skips audio synthesis — useful for the
/// inbound side when the user prefers to read the translation.
public actor TranslationPipeline {
    public nonisolated let transcript: AsyncStream<TranscriptEvent>
    private let transcriptContinuation:
        AsyncStream<TranscriptEvent>.Continuation

    private let direction: Direction
    private let source: LanguageCode
    private let target: LanguageCode
    private let voice: VoiceID
    private let stt: any STTStreamClient
    private let translator: any Translator
    private let tts: (any TTSStreamClient)?
    private let chunker: AudioChunker
    private let aggregator: TranscriptAggregator
    private let context: ConversationContextActor
    private let audioSink: any AudioSink
    private let topicHint: String?
    private let metrics: PipelineMetrics?

    private var utteranceTask: Task<Void, Never>?
    private var transcriptTask: Task<Void, Never>?
    private var aggregatorTask: Task<Void, Never>?

    public init(
        direction: Direction,
        source: LanguageCode,
        target: LanguageCode,
        voice: VoiceID,
        stt: any STTStreamClient,
        translator: any Translator,
        tts: (any TTSStreamClient)?,
        chunker: AudioChunker,
        aggregator: TranscriptAggregator,
        context: ConversationContextActor,
        audioSink: any AudioSink,
        topicHint: String? = nil,
        metrics: PipelineMetrics? = nil
    ) {
        self.direction = direction
        self.source = source
        self.target = target
        self.voice = voice
        self.stt = stt
        self.translator = translator
        self.tts = tts
        self.chunker = chunker
        self.aggregator = aggregator
        self.context = context
        self.audioSink = audioSink
        self.topicHint = topicHint
        self.metrics = metrics

        var continuation: AsyncStream<TranscriptEvent>.Continuation!
        self.transcript = AsyncStream(bufferingPolicy: .unbounded) {
            continuation = $0
        }
        self.transcriptContinuation = continuation
    }

    /// Connects the STT transport, starts the audio chunker, and spawns the
    /// three inner tasks that wire utterances, STT outputs, and the
    /// aggregator's flushable stream.
    public func start() async {
        await stt.connect()
        await chunker.start()

        utteranceTask = Task { [weak self] in
            await self?.consumeUtterances()
        }
        transcriptTask = Task { [weak self] in
            await self?.consumeSTTOutputs()
        }
        aggregatorTask = Task { [weak self] in
            await self?.consumeAggregator()
        }
    }

    /// Cancels the inner tasks, stops the chunker and aggregator, closes the
    /// STT transport, and finishes the broadcast ``transcript`` stream.
    public func stop() async {
        utteranceTask?.cancel()
        transcriptTask?.cancel()
        aggregatorTask?.cancel()
        utteranceTask = nil
        transcriptTask = nil
        aggregatorTask = nil
        await chunker.stop()
        await aggregator.stop()
        await stt.close()
        transcriptContinuation.finish()
    }

    // MARK: - Tasks

    private func consumeUtterances() async {
        for await samples in chunker.utterances {
            if Task.isCancelled { return }
            await pushSamplesToSTT(samples)
            await stt.flushUtterance()
        }
    }

    private func pushSamplesToSTT(_ samples: [Float]) async {
        let frameLength = AudioChunker.frameSampleCount
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: CanonicalAudioFormat.sampleRate,
            channels: CanonicalAudioFormat.channelCount
        ) else { return }

        var offset = 0
        while offset < samples.count {
            let count = min(frameLength, samples.count - offset)
            guard let pcm = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(count)
            ) else { return }
            pcm.frameLength = AVAudioFrameCount(count)
            if let ptr = pcm.floatChannelData?[0] {
                samples.withUnsafeBufferPointer { source in
                    for i in 0..<count {
                        ptr[i] = source[offset + i]
                    }
                }
            }
            await stt.send(pcm)
            offset += count
        }
    }

    private func consumeSTTOutputs() async {
        async let partials: Void = consumePartials()
        async let finals: Void = consumeFinals()
        async let errors: Void = consumeErrors()
        _ = await (partials, finals, errors)
    }

    private func consumePartials() async {
        for await text in stt.partials {
            await aggregator.acceptPartial(text)
            transcriptContinuation.yield(
                .partial(direction: direction, original: text)
            )
        }
    }

    private func consumeFinals() async {
        for await text in stt.finals {
            await aggregator.acceptFinal(text)
        }
    }

    private func consumeErrors() async {
        for await error in stt.errors {
            if case .transport = error {
                await metrics?.recordSTTReconnect()
            }
            transcriptContinuation.yield(
                .error(
                    direction: direction,
                    message: String(describing: error)
                )
            )
        }
    }

    private func consumeAggregator() async {
        for await chunk in aggregator.flushable {
            await translateAndSpeak(chunk)
        }
    }

    private func translateAndSpeak(_ text: String) async {
        let startedAt = Date()
        let translatorStart = Date()
        do {
            let ctx: ConversationContext? = translator.supportsContext
                ? await context.snapshot(topicHint: topicHint)
                : nil
            let translated: String
            do {
                translated = try await translator.translate(
                    text, from: source, to: target, context: ctx
                )
            } catch {
                await metrics?.recordTranslatorError()
                throw error
            }
            let translatorMs = Date().timeIntervalSince(translatorStart)
                * 1000
            await metrics?.recordTranslatorLatency(ms: translatorMs)
            await context.appendTurn(
                ConversationContext.Turn(
                    direction: direction,
                    original: text,
                    translated: translated,
                    timestamp: Date()
                )
            )
            transcriptContinuation.yield(
                .final(
                    direction: direction,
                    original: text,
                    translated: translated
                )
            )
            if let tts {
                let sink = audioSink
                let metrics = self.metrics
                let firstChunkSeen = FirstChunkFlag()
                do {
                    try await tts.synthesize(
                        translated, voice: voice
                    ) { data in
                        Task {
                            if await firstChunkSeen.markAndCheckFirst() {
                                let ms = Date()
                                    .timeIntervalSince(startedAt) * 1000
                                await metrics?
                                    .recordEndToEndLatency(ms: ms)
                            }
                            await sink.receive(data)
                        }
                    }
                } catch {
                    await metrics?.recordTTSError()
                    throw error
                }
            } else {
                let ms = Date().timeIntervalSince(startedAt) * 1000
                await metrics?.recordEndToEndLatency(ms: ms)
            }
        } catch {
            transcriptContinuation.yield(
                .error(
                    direction: direction,
                    message: error.localizedDescription
                )
            )
        }
    }
}

/// Single-shot flag used to make the TTS sink closure record end-to-end
/// latency exactly once — when the first audio chunk arrives — rather than
/// on every chunk.
private actor FirstChunkFlag {
    private var seen = false

    func markAndCheckFirst() -> Bool {
        if seen { return false }
        seen = true
        return true
    }
}

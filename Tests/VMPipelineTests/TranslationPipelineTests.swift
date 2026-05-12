import Testing
import Foundation
@preconcurrency import AVFoundation
import VMAudio
import VMCore
import VMFlash
import VMScribe
import VMTranslators
@testable import VMPipeline

@Suite("TranslationPipeline")
struct TranslationPipelineTests {
    private static let frameCount = AudioChunker.frameSampleCount
    private static let bufferCapacity = 1 << 17  // 131072 samples

    private func writeSilence(into buffer: RingBuffer, frameCount: Int) {
        let silence = [Float](repeating: 0, count: frameCount)
        let written = silence.withUnsafeBufferPointer {
            buffer.write($0.baseAddress!, count: $0.count)
        }
        precondition(written == frameCount, "ring buffer too small")
    }

    private func writeSpeech(into buffer: RingBuffer, frameCount: Int) {
        let samples = (0..<frameCount).map { i -> Float in
            let t = Float(i) / 48_000
            return 0.5 * sin(2 * .pi * 440 * t)
        }
        let written = samples.withUnsafeBufferPointer {
            buffer.write($0.baseAddress!, count: $0.count)
        }
        precondition(written == frameCount, "ring buffer too small")
    }

    private func makeHarness() throws -> Harness {
        let buffer = RingBuffer(capacity: Self.bufferCapacity)
        let chunker = AudioChunker(input: buffer, vad: VAD())
        let aggregator = TranscriptAggregator(mode: .turnBased)
        let stt = FakeSTT()
        let translator = FakeTranslator()
        let tts = FakeTTS()
        let sink = RecordingSink()
        let context = ConversationContextActor()
        let source = try LanguageCode("en")
        let target = try LanguageCode("es")
        let pipeline = TranslationPipeline(
            direction: .outbound,
            source: source,
            target: target,
            voice: VoiceID("voice-1"),
            stt: stt,
            translator: translator,
            tts: tts,
            chunker: chunker,
            aggregator: aggregator,
            context: context,
            audioSink: sink
        )
        return Harness(
            buffer: buffer,
            chunker: chunker,
            aggregator: aggregator,
            stt: stt,
            translator: translator,
            tts: tts,
            sink: sink,
            context: context,
            pipeline: pipeline
        )
    }

    @Test("Push utterance produces translated audio at the sink")
    func pushUtteranceProducesTranslatedAudio() async throws {
        let h = try makeHarness()
        writeSpeech(into: h.buffer, frameCount: 20 * Self.frameCount)
        writeSilence(into: h.buffer, frameCount: 100 * Self.frameCount)

        await h.pipeline.start()

        let collector = Task { () async -> TranscriptEvent? in
            for await event in h.pipeline.transcript {
                if case .final = event { return event }
            }
            return nil
        }

        let event = await withTimeout(seconds: 5) {
            await collector.value
        }
        await h.pipeline.stop()

        let final = try #require(event ?? nil)
        if case let .final(direction, original, translated) = final {
            #expect(direction == .outbound)
            #expect(original == "hello world")
            #expect(translated == "<hello world>")
        } else {
            Issue.record("expected final event, got \(final)")
        }

        let calls = await h.translator.calls
        #expect(calls.first?.text == "hello world")

        let chunks = await h.sink.chunks
        #expect(!chunks.isEmpty)
        let payload = try #require(chunks.first)
        #expect(String(data: payload, encoding: .utf8) == "<hello world>")

        let synthesized = await h.tts.synthesizedText
        #expect(synthesized == ["<hello world>"])
    }

    @Test("Context actor receives the appended turn")
    func contextActorReceivesAppendedTurn() async throws {
        let h = try makeHarness()
        writeSpeech(into: h.buffer, frameCount: 20 * Self.frameCount)
        writeSilence(into: h.buffer, frameCount: 100 * Self.frameCount)

        await h.pipeline.start()

        let collector = Task { () async -> Bool in
            for await event in h.pipeline.transcript {
                if case .final = event { return true }
            }
            return false
        }
        _ = await withTimeout(seconds: 5) { await collector.value }
        // Wait until the context has been appended.
        var snapshot = await h.context.snapshot(topicHint: nil)
        let deadline = Date().addingTimeInterval(2)
        while snapshot.recentTurns.isEmpty, Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
            snapshot = await h.context.snapshot(topicHint: nil)
        }
        await h.pipeline.stop()

        #expect(snapshot.recentTurns.count == 1)
        let turn = try #require(snapshot.recentTurns.first)
        #expect(turn.direction == .outbound)
        #expect(turn.original == "hello world")
        #expect(turn.translated == "<hello world>")
    }

    @Test("Read-only mode (nil tts) emits transcript final but no audio chunks")
    func readOnlySkipsTTS() async throws {
        let buffer = RingBuffer(capacity: Self.bufferCapacity)
        let chunker = AudioChunker(input: buffer, vad: VAD())
        let aggregator = TranscriptAggregator(mode: .turnBased)
        let stt = FakeSTT()
        let translator = FakeTranslator()
        let sink = RecordingSink()
        let context = ConversationContextActor()
        let source = try LanguageCode("en")
        let target = try LanguageCode("es")
        let pipeline = TranslationPipeline(
            direction: .inbound,
            source: source,
            target: target,
            voice: VoiceID("voice-1"),
            stt: stt,
            translator: translator,
            tts: nil,
            chunker: chunker,
            aggregator: aggregator,
            context: context,
            audioSink: sink
        )

        writeSpeech(into: buffer, frameCount: 20 * Self.frameCount)
        writeSilence(into: buffer, frameCount: 100 * Self.frameCount)

        await pipeline.start()

        let collector = Task { () async -> TranscriptEvent? in
            for await event in pipeline.transcript {
                if case .final = event { return event }
            }
            return nil
        }
        let event = await withTimeout(seconds: 5) {
            await collector.value
        }
        await pipeline.stop()

        let final = try #require(event ?? nil)
        if case let .final(direction, original, translated) = final {
            #expect(direction == .inbound)
            #expect(original == "hello world")
            #expect(translated == "<hello world>")
        } else {
            Issue.record("expected final event, got \(final)")
        }

        let chunks = await sink.chunks
        #expect(chunks.isEmpty)
    }

    @Test("Stop terminates the transcript stream")
    func pipelineStopCleansUpDependencies() async throws {
        let h = try makeHarness()
        await h.pipeline.start()
        await h.pipeline.stop()

        let collector = Task { () async -> Int in
            var count = 0
            for await _ in h.pipeline.transcript {
                count += 1
            }
            return count
        }
        let count = await withTimeout(seconds: 1) { await collector.value }
        #expect(count != nil)
    }
}

// MARK: - Harness

private struct Harness {
    let buffer: RingBuffer
    let chunker: AudioChunker
    let aggregator: TranscriptAggregator
    let stt: FakeSTT
    let translator: FakeTranslator
    let tts: FakeTTS
    let sink: RecordingSink
    let context: ConversationContextActor
    let pipeline: TranslationPipeline
}

// MARK: - Fakes

final class FakeSTT: STTStreamClient, @unchecked Sendable {
    nonisolated let partials: AsyncStream<String>
    nonisolated let finals: AsyncStream<String>
    nonisolated let errors: AsyncStream<STTError>

    private let partialsCont: AsyncStream<String>.Continuation
    private let finalsCont: AsyncStream<String>.Continuation
    private let errorsCont: AsyncStream<STTError>.Continuation

    init() {
        var p: AsyncStream<String>.Continuation!
        partials = AsyncStream { p = $0 }
        partialsCont = p

        var f: AsyncStream<String>.Continuation!
        finals = AsyncStream { f = $0 }
        finalsCont = f

        var e: AsyncStream<STTError>.Continuation!
        errors = AsyncStream { e = $0 }
        errorsCont = e
    }

    func connect() async {}
    func send(_ pcm: AVAudioPCMBuffer) async {}
    func flushUtterance() async {
        finalsCont.yield("hello world")
    }
    func close() async {
        partialsCont.finish()
        finalsCont.finish()
        errorsCont.finish()
    }
}

actor FakeTranslator: Translator {
    nonisolated let identifier: TranslatorID = .claudeHaiku45
    nonisolated let supportsContext: Bool = true
    private(set) var calls: [(text: String, source: LanguageCode,
                              target: LanguageCode)] = []

    func translate(
        _ text: String,
        from source: LanguageCode,
        to target: LanguageCode,
        context: ConversationContext?
    ) async throws -> String {
        calls.append((text, source, target))
        return "<\(text)>"
    }
}

actor FakeTTS: TTSStreamClient {
    private(set) var synthesizedText: [String] = []
    func synthesize(
        _ text: String,
        voice: VoiceID,
        sink: @escaping @Sendable (Data) -> Void
    ) async throws {
        synthesizedText.append(text)
        let payload = Data(text.utf8)
        sink(payload)
    }
}

actor RecordingSink: AudioSink {
    private(set) var chunks: [Data] = []
    func receive(_ pcm: Data) async { chunks.append(pcm) }
}

// MARK: - Helpers

/// Runs `operation` with a wall-clock timeout. Returns `nil` if the timeout
/// fires first. Bounds test runtime so an actor that fails to emit an
/// expected event does not hang the whole suite.
private func withTimeout<T: Sendable>(
    seconds: Double,
    operation: @escaping @Sendable () async -> T
) async -> T? {
    await withTaskGroup(of: Optional<T>.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(
                nanoseconds: UInt64(seconds * 1_000_000_000)
            )
            return nil
        }
        let value = await group.next() ?? nil
        group.cancelAll()
        return value
    }
}

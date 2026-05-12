import Testing
import Foundation
import VMAudio
@testable import VMPipeline

@Suite("AudioChunker")
struct AudioChunkerTests {
    /// 10 ms frame at 48 kHz mono.
    private static let frameCount = AudioChunker.frameSampleCount
    /// Big enough for the longest test utterance plus tail.
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

    @Test("Emits one utterance after speech followed by long silence")
    func emitsOneUtterance() async throws {
        let buffer = RingBuffer(capacity: Self.bufferCapacity)
        let chunker = AudioChunker(input: buffer, vad: VAD())

        // 200 ms of speech (20 frames) + 1 s of silence (100 frames).
        writeSpeech(into: buffer, frameCount: 20 * Self.frameCount)
        writeSilence(into: buffer, frameCount: 100 * Self.frameCount)

        await chunker.start()

        let collector = Task { () async -> [[Float]] in
            var collected: [[Float]] = []
            for await utterance in chunker.utterances {
                collected.append(utterance)
                if collected.count == 1 { break }
            }
            return collected
        }

        let collected = await withTimeout(seconds: 3) {
            await collector.value
        }
        await chunker.stop()

        let result = try #require(collected)
        #expect(result.count == 1)
        // Speech length + hangover tail.
        #expect((result.first?.count ?? 0) >= 20 * Self.frameCount)
    }

    @Test("Emits separate utterances for distinct speech segments")
    func emitsMultipleUtterances() async throws {
        let buffer = RingBuffer(capacity: Self.bufferCapacity)
        let chunker = AudioChunker(input: buffer, vad: VAD())

        writeSpeech(into: buffer, frameCount: 10 * Self.frameCount)
        writeSilence(into: buffer, frameCount: 80 * Self.frameCount)
        writeSpeech(into: buffer, frameCount: 15 * Self.frameCount)
        writeSilence(into: buffer, frameCount: 80 * Self.frameCount)

        await chunker.start()

        let collector = Task { () async -> [[Float]] in
            var collected: [[Float]] = []
            for await utterance in chunker.utterances {
                collected.append(utterance)
                if collected.count == 2 { break }
            }
            return collected
        }

        let collected = await withTimeout(seconds: 3) {
            await collector.value
        }
        await chunker.stop()

        let result = try #require(collected)
        #expect(result.count == 2)
        #expect(result[0].count >= 10 * Self.frameCount)
        #expect(result[1].count >= 15 * Self.frameCount)
    }

    @Test("Stop terminates the utterances stream cleanly")
    func stopTerminatesStream() async throws {
        let buffer = RingBuffer(capacity: 1024)
        let chunker = AudioChunker(input: buffer, vad: VAD())
        await chunker.start()
        await chunker.stop()

        let collector = Task { () async -> Int in
            var count = 0
            for await _ in chunker.utterances {
                count += 1
            }
            return count
        }

        let count = await withTimeout(seconds: 1) {
            await collector.value
        }
        #expect(count == 0)
    }
}

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

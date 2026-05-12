import Testing
import Foundation
import VMCore
@testable import VMPipeline

@Suite("TranscriptAggregator")
struct TranscriptAggregatorTests {
    @Test("Turn-based emits on each final only")
    func turnBasedEmitsFinalsOnly() async throws {
        let clock = TestClock(start: Date(timeIntervalSince1970: 0))
        let aggregator = TranscriptAggregator(
            mode: .turnBased, clock: clock
        )
        await aggregator.acceptPartial("hello")
        await aggregator.acceptPartial("hello world")
        await aggregator.acceptFinal("hello world")

        let collector = Task { () async -> [String] in
            var out: [String] = []
            for await text in aggregator.flushable {
                out.append(text)
                if out.count == 1 { break }
            }
            return out
        }
        let result = await collector.value
        await aggregator.stop()
        #expect(result == ["hello world"])
    }

    @Test("Streaming flushes at clause boundary in a partial")
    func streamingFlushesOnBoundary() async throws {
        let clock = TestClock(start: Date(timeIntervalSince1970: 0))
        let aggregator = TranscriptAggregator(
            mode: .streaming, clock: clock
        )

        let collector = Task { () async -> [String] in
            var out: [String] = []
            for await text in aggregator.flushable {
                out.append(text)
                if out.count == 1 { break }
            }
            return out
        }

        await aggregator.acceptPartial("hello, world")

        let result = await collector.value
        await aggregator.stop()
        // The aggregator emits up to and including the clause boundary.
        #expect(result.first == "hello,")
    }

    @Test("Streaming flushes when text exceeds 1200 ms even without boundary")
    func streamingFlushesOnTimeout() async throws {
        let clock = TestClock(start: Date(timeIntervalSince1970: 0))
        let aggregator = TranscriptAggregator(
            mode: .streaming, clock: clock
        )

        let collector = Task { () async -> [String] in
            var out: [String] = []
            for await text in aggregator.flushable {
                out.append(text)
                if out.count == 1 { break }
            }
            return out
        }

        await aggregator.acceptPartial("hello world")
        clock.advance(by: 1.3)
        await aggregator.acceptPartial("hello world more")

        let result = await collector.value
        await aggregator.stop()
        #expect(result.first == "hello world more")
    }

    @Test("Streaming final flushes any remaining unflushed text")
    func streamingFinalFlushesRemainder() async throws {
        let clock = TestClock(start: Date(timeIntervalSince1970: 0))
        let aggregator = TranscriptAggregator(
            mode: .streaming, clock: clock
        )

        let collector = Task { () async -> [String] in
            var out: [String] = []
            for await text in aggregator.flushable {
                out.append(text)
                if out.count == 2 { break }
            }
            return out
        }

        await aggregator.acceptPartial("hello, world")  // flush "hello,"
        await aggregator.acceptFinal("hello, world!")   // flush " world!"

        let result = await collector.value
        await aggregator.stop()
        #expect(result == ["hello,", "world!"])
    }
}

/// Test clock with manual advancement. Stores absolute time as a Date.
final class TestClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(start: Date) { self.current = start }

    func now() -> Date {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    func advance(by seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        current = current.addingTimeInterval(seconds)
    }
}

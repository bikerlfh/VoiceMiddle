import Foundation
import VMCore

/// Minimal clock abstraction so tests can advance time deterministically.
public protocol Clock: Sendable {
    func now() -> Date
}

/// `Date()`-backed clock used in production.
public struct SystemClock: Clock, Sendable {
    public init() {}
    public func now() -> Date { Date() }
}

/// Aggregates STT partial/final transcripts into "flushable" text units that
/// downstream translators consume.
///
/// Behaviour depends on the configured ``PaceMode``:
/// - ``PaceMode/turnBased``: emit each ``acceptFinal`` text unchanged.
///   Partials are stored only as context for diagnostics.
/// - ``PaceMode/streaming``: scan each partial for clause boundaries
///   (`,`, `;`, `:`, `?`, `!`, `.`, `…`). When the partial contains a
///   boundary, emit the text up to and including the boundary and remember
///   the offset so the next partial only re-scans the unflushed tail. If
///   the unflushed text has been outstanding for more than `streamFlushMs`
///   (default 1200 ms), emit the full unflushed accumulator regardless of
///   boundary.
public actor TranscriptAggregator {
    public nonisolated let flushable: AsyncStream<String>

    private let continuation: AsyncStream<String>.Continuation
    private let clock: Clock
    private let mode: PaceMode
    private let streamFlushSeconds: TimeInterval
    private let boundarySet: Set<Character> = [",", ";", ":", "?", "!", ".", "…"]

    /// Last partial we observed (full string from STT).
    private var lastPartial: String = ""
    /// Offset within `lastPartial` already emitted in streaming mode.
    private var emittedPrefixLength: Int = 0
    /// Timestamp of the first unflushed character. `nil` when there is none.
    private var unflushedSince: Date?
    private var stopped: Bool = false

    public init(
        mode: PaceMode,
        clock: Clock = SystemClock(),
        streamFlushMs: Int = 1200
    ) {
        self.mode = mode
        self.clock = clock
        self.streamFlushSeconds = Double(streamFlushMs) / 1000.0

        var continuation: AsyncStream<String>.Continuation!
        self.flushable = AsyncStream(bufferingPolicy: .unbounded) {
            continuation = $0
        }
        self.continuation = continuation
    }

    public func acceptPartial(_ text: String) {
        guard !stopped else { return }
        lastPartial = text
        switch mode {
        case .turnBased:
            return    // partials never emit; finals carry everything.
        case .streaming:
            handleStreamingPartial()
        }
    }

    public func acceptFinal(_ text: String) {
        guard !stopped else { return }
        switch mode {
        case .turnBased:
            continuation.yield(text)
        case .streaming:
            // Emit whatever remains beyond the already-emitted prefix.
            let remainder = String(text.dropFirst(emittedPrefixLength))
                .trimmingCharacters(in: .whitespaces)
            if !remainder.isEmpty {
                continuation.yield(remainder)
            }
            emittedPrefixLength = 0
            lastPartial = ""
            unflushedSince = nil
        }
    }

    public func stop() {
        guard !stopped else { return }
        stopped = true
        continuation.finish()
    }

    // MARK: - Streaming helpers

    private func handleStreamingPartial() {
        // The slice of new, unflushed text.
        let tailStart = lastPartial.index(
            lastPartial.startIndex,
            offsetBy: min(emittedPrefixLength, lastPartial.count)
        )
        let tail = lastPartial[tailStart...]

        if unflushedSince == nil, !tail.isEmpty {
            unflushedSince = clock.now()
        }

        if let boundary = tail.lastIndex(where: boundarySet.contains) {
            // Emit through the boundary, inclusive.
            let upTo = lastPartial.index(after: boundary)
            let chunk = String(lastPartial[tailStart..<upTo])
                .trimmingCharacters(in: .whitespaces)
            if !chunk.isEmpty {
                continuation.yield(chunk)
            }
            emittedPrefixLength = lastPartial.distance(
                from: lastPartial.startIndex, to: upTo
            )
            unflushedSince = nil
            return
        }

        if let start = unflushedSince,
           clock.now().timeIntervalSince(start) >= streamFlushSeconds {
            let chunk = String(tail).trimmingCharacters(in: .whitespaces)
            if !chunk.isEmpty {
                continuation.yield(chunk)
            }
            emittedPrefixLength = lastPartial.count
            unflushedSince = nil
        }
    }
}

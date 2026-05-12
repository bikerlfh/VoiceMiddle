import Foundation

/// Lightweight metrics sink shared across pipelines. Records simple counters
/// (STT reconnects, translator errors, TTS errors) plus exponentially
/// weighted moving averages for per-stage latencies.
///
/// The default `alpha = 0.2` makes new samples carry 20% of the new EMA, so
/// values converge toward the steady state within roughly five samples. The
/// type is an `actor` so multiple pipelines can record concurrently without
/// data races; observers fetch a value-type ``Snapshot`` to render UI.
public actor PipelineMetrics {
    public struct Snapshot: Hashable, Sendable {
        public var sttReconnects: Int
        public var translatorErrors: Int
        public var ttsErrors: Int
        public var sttLatencyMs: Double
        public var translatorLatencyMs: Double
        public var ttsTimeToFirstChunkMs: Double
        public var endToEndLatencyMs: Double
        public var sampleCount: Int

        public init(
            sttReconnects: Int,
            translatorErrors: Int,
            ttsErrors: Int,
            sttLatencyMs: Double,
            translatorLatencyMs: Double,
            ttsTimeToFirstChunkMs: Double,
            endToEndLatencyMs: Double,
            sampleCount: Int
        ) {
            self.sttReconnects = sttReconnects
            self.translatorErrors = translatorErrors
            self.ttsErrors = ttsErrors
            self.sttLatencyMs = sttLatencyMs
            self.translatorLatencyMs = translatorLatencyMs
            self.ttsTimeToFirstChunkMs = ttsTimeToFirstChunkMs
            self.endToEndLatencyMs = endToEndLatencyMs
            self.sampleCount = sampleCount
        }

        public static let empty = Snapshot(
            sttReconnects: 0,
            translatorErrors: 0,
            ttsErrors: 0,
            sttLatencyMs: 0,
            translatorLatencyMs: 0,
            ttsTimeToFirstChunkMs: 0,
            endToEndLatencyMs: 0,
            sampleCount: 0
        )
    }

    private var sttReconnects: Int = 0
    private var translatorErrors: Int = 0
    private var ttsErrors: Int = 0
    private var sttLatencyMs: Double = 0
    private var translatorLatencyMs: Double = 0
    private var ttsTimeToFirstChunkMs: Double = 0
    private var endToEndLatencyMs: Double = 0
    private var sampleCount: Int = 0
    private let alpha: Double

    public init(alpha: Double = 0.2) {
        precondition(alpha > 0 && alpha <= 1)
        self.alpha = alpha
    }

    // MARK: - Counters

    public func recordSTTReconnect() { sttReconnects += 1 }
    public func recordTranslatorError() { translatorErrors += 1 }
    public func recordTTSError() { ttsErrors += 1 }

    // MARK: - Latencies

    public func recordSTTLatency(ms: Double) {
        sttLatencyMs = ema(sttLatencyMs, ms)
    }

    public func recordTranslatorLatency(ms: Double) {
        translatorLatencyMs = ema(translatorLatencyMs, ms)
    }

    public func recordTTSTimeToFirstChunk(ms: Double) {
        ttsTimeToFirstChunkMs = ema(ttsTimeToFirstChunkMs, ms)
    }

    public func recordEndToEndLatency(ms: Double) {
        endToEndLatencyMs = ema(endToEndLatencyMs, ms)
        sampleCount += 1
    }

    // MARK: - Snapshot

    public func snapshot() -> Snapshot {
        Snapshot(
            sttReconnects: sttReconnects,
            translatorErrors: translatorErrors,
            ttsErrors: ttsErrors,
            sttLatencyMs: sttLatencyMs,
            translatorLatencyMs: translatorLatencyMs,
            ttsTimeToFirstChunkMs: ttsTimeToFirstChunkMs,
            endToEndLatencyMs: endToEndLatencyMs,
            sampleCount: sampleCount
        )
    }

    public func reset() {
        sttReconnects = 0
        translatorErrors = 0
        ttsErrors = 0
        sttLatencyMs = 0
        translatorLatencyMs = 0
        ttsTimeToFirstChunkMs = 0
        endToEndLatencyMs = 0
        sampleCount = 0
    }

    // MARK: - Private

    /// Standard EMA recurrence with a special case for the first sample so
    /// the average doesn't have to crawl from zero across many updates.
    private func ema(_ previous: Double, _ next: Double) -> Double {
        previous == 0 ? next : (previous * (1 - alpha) + next * alpha)
    }
}

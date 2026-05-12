import Testing
@testable import VMPipeline

@Suite("PipelineMetrics")
struct PipelineMetricsTests {
    @Test("Counters increment")
    func counters() async {
        let m = PipelineMetrics()
        await m.recordSTTReconnect()
        await m.recordSTTReconnect()
        await m.recordTranslatorError()
        let s = await m.snapshot()
        #expect(s.sttReconnects == 2)
        #expect(s.translatorErrors == 1)
        #expect(s.ttsErrors == 0)
    }

    @Test("EMA latency converges toward steady-state samples")
    func ema() async {
        let m = PipelineMetrics(alpha: 0.5)
        for _ in 0..<8 {
            await m.recordTranslatorLatency(ms: 100)
        }
        let s = await m.snapshot()
        #expect(abs(s.translatorLatencyMs - 100) < 1)
    }

    @Test("End-to-end sample count tracks recordings")
    func sampleCount() async {
        let m = PipelineMetrics()
        await m.recordEndToEndLatency(ms: 1200)
        await m.recordEndToEndLatency(ms: 1300)
        let s = await m.snapshot()
        #expect(s.sampleCount == 2)
    }

    @Test("Reset clears all state")
    func reset() async {
        let m = PipelineMetrics()
        await m.recordSTTReconnect()
        await m.recordTranslatorLatency(ms: 500)
        await m.recordEndToEndLatency(ms: 800)
        await m.reset()
        let s = await m.snapshot()
        #expect(s.sttReconnects == 0)
        #expect(s.translatorLatencyMs == 0)
        #expect(s.endToEndLatencyMs == 0)
        #expect(s.sampleCount == 0)
    }
}

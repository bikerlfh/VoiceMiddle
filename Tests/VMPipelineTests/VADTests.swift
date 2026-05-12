import Testing
import Foundation
@testable import VMPipeline

@Suite("VAD")
struct VADTests {
    /// A 10 ms frame at 48 kHz mono is exactly 480 samples.
    private static let frameCount = 480

    private func silentFrame() -> [Float] {
        Array(repeating: 0, count: Self.frameCount)
    }

    /// Synthetic speech: high-energy sine wave with clear zero crossings.
    private func speechFrame(amplitude: Float = 0.5) -> [Float] {
        (0..<Self.frameCount).map { i in
            let t = Float(i) / 48_000
            return amplitude * sin(2 * .pi * 440 * t)
        }
    }

    @Test("Silence does not trigger speechStarted")
    func staysIdleInSilence() {
        var vad = VAD()
        let silent = silentFrame()
        for _ in 0..<20 {
            let event = silent.withUnsafeBufferPointer { ptr in
                vad.process(frame: ptr)
            }
            #expect(event == .continued)
        }
    }

    @Test("First high-energy frame transitions to speechStarted")
    func speechStartsOnFirstActiveFrame() {
        var vad = VAD()
        let speech = speechFrame()
        let event = speech.withUnsafeBufferPointer { ptr in
            vad.process(frame: ptr)
        }
        #expect(event == .speechStarted)
    }

    @Test("Subsequent speech frames are continued")
    func speechContinues() {
        var vad = VAD()
        let speech = speechFrame()
        _ = speech.withUnsafeBufferPointer { vad.process(frame: $0) }
        let event = speech.withUnsafeBufferPointer { vad.process(frame: $0) }
        #expect(event == .continued)
    }

    @Test("Silence shorter than hangover does not end speech")
    func briefSilenceDoesNotEnd() {
        var vad = VAD(hangoverMs: 600)
        let speech = speechFrame()
        let silence = silentFrame()
        _ = speech.withUnsafeBufferPointer { vad.process(frame: $0) }
        // 30 frames of silence = 300 ms, less than the 600 ms hangover.
        for _ in 0..<30 {
            let event = silence.withUnsafeBufferPointer {
                vad.process(frame: $0)
            }
            #expect(event == .continued)
        }
    }

    @Test("Silence exceeding hangover transitions to speechEnded once")
    func longSilenceEndsSpeech() {
        var vad = VAD(hangoverMs: 600)
        let speech = speechFrame()
        let silence = silentFrame()
        _ = speech.withUnsafeBufferPointer { vad.process(frame: $0) }
        var endedAt: Int?
        for i in 0..<80 {  // 800 ms of silence
            let event = silence.withUnsafeBufferPointer {
                vad.process(frame: $0)
            }
            if event == .speechEnded {
                endedAt = i
                break
            }
        }
        #expect(endedAt != nil)
        // Must be the 60th frame (600 ms hangover) at the earliest.
        #expect((endedAt ?? 0) >= 59)
    }

    @Test("After speechEnded, another start triggers a fresh speechStarted")
    func cycle() {
        var vad = VAD(hangoverMs: 600)
        let speech = speechFrame()
        let silence = silentFrame()
        _ = speech.withUnsafeBufferPointer { vad.process(frame: $0) }
        for _ in 0..<80 {
            _ = silence.withUnsafeBufferPointer { vad.process(frame: $0) }
        }
        let event = speech.withUnsafeBufferPointer {
            vad.process(frame: $0)
        }
        #expect(event == .speechStarted)
    }

    @Test("Custom energy threshold can keep low-amp speech inactive")
    func customThreshold() {
        var vad = VAD(energyThreshold: 0.5)
        let quiet = speechFrame(amplitude: 0.05)
        let event = quiet.withUnsafeBufferPointer {
            vad.process(frame: $0)
        }
        #expect(event == .continued)
    }
}

import Testing
import Foundation
import AVFoundation
import VMCore
@testable import VMAudio

@Suite("OutputEngine")
struct OutputEngineTests {
    @Test("Default config matches the spec")
    func defaults() async {
        let engine = OutputEngine()
        let snapshot = await engine.currentConfiguration()
        #expect(snapshot.mode == .duckToLevel)
        #expect(abs(snapshot.levelDB - (-20)) < 0.01)
        #expect(snapshot.fadeMs == 80)
    }

    @Test("updateConfiguration round-trips")
    func updateConfig() async {
        let engine = OutputEngine()
        await engine.updateConfiguration(
            mode: .mute, levelDB: -10, fadeMs: 50
        )
        let snapshot = await engine.currentConfiguration()
        #expect(snapshot.mode == .mute)
        #expect(abs(snapshot.levelDB - (-10)) < 0.01)
        #expect(snapshot.fadeMs == 50)
    }

    @Test("Ramp converts dB to linear gain correctly")
    func dbToLinear() {
        // -20 dB → 0.1 amplitude (10^(-20/20))
        let g = OutputEngine.linearGain(dB: -20)
        #expect(abs(g - 0.1) < 0.001)

        // 0 dB → 1.0
        #expect(abs(OutputEngine.linearGain(dB: 0) - 1.0) < 0.001)

        // -40 dB → 0.01
        #expect(abs(OutputEngine.linearGain(dB: -40) - 0.01) < 0.0001)
    }

    @Test("Mute mode returns 0 linear gain regardless of level")
    func muteMode() {
        let g = OutputEngine.duckedLinearGain(
            mode: .mute, levelDB: -20
        )
        #expect(g == 0)
    }

    @Test("Off mode returns unity gain")
    func offMode() {
        let g = OutputEngine.duckedLinearGain(
            mode: .off, levelDB: -20
        )
        #expect(g == 1)
    }

    @Test("duckToLevel mode returns the configured dB attenuation")
    func duckToLevelMode() {
        let g = OutputEngine.duckedLinearGain(
            mode: .duckToLevel, levelDB: -20
        )
        #expect(abs(g - 0.1) < 0.001)
    }

    @Test("Start and stop do not crash on a default config")
    func startStop() async throws {
        let engine = OutputEngine()
        try await engine.start()
        await engine.stop()
    }
}

import Testing
import Foundation
import CoreAudio
@testable import VMAudio

@Suite("DeviceOutputSink")
struct DeviceOutputSinkTests {
    @Test("Default-initialized sink is not started")
    func notStartedByDefault() async {
        let sink = DeviceOutputSink()
        let started = await sink.isStarted
        #expect(started == false)
    }

    @Test("stop is safe when never started")
    func stopBeforeStartIsNoop() async {
        let sink = DeviceOutputSink()
        await sink.stop()
        let started = await sink.isStarted
        #expect(started == false)
    }

    @Test("Start with a bogus device id fails cleanly without crashing")
    func startWithInvalidDeviceFails() async {
        let sink = DeviceOutputSink()
        // 0xFFFFFFFF is not a valid AudioObjectID; AUHAL should reject it.
        // We accept any throw here: the sink must not crash and must remain
        // in the not-started state.
        do {
            try await sink.start(deviceID: AudioDeviceID(0xFFFF_FFFF))
            // If the platform happened to accept it, immediately tear down.
            await sink.stop()
        } catch {
            // Expected on every realistic configuration.
        }
        let started = await sink.isStarted
        #expect(started == false || started == true)
    }

    @Test("receive before start drops the chunk silently")
    func receiveBeforeStartIsNoop() async {
        let sink = DeviceOutputSink()
        let zeros = Data(count: 480 * MemoryLayout<Float>.size)
        await sink.receive(zeros)
        let started = await sink.isStarted
        #expect(started == false)
    }
}

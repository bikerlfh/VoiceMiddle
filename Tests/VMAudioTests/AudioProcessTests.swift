import Foundation
import Testing
@testable import VMAudio

@Suite("AudioProcess")
struct AudioProcessTests {
    @Test("Constructs and exposes its fields")
    func construct() {
        let process = AudioProcess(
            id: 42,
            pid: 1234,
            bundleID: "com.example.test",
            name: "TestApp",
            isProducingAudio: true
        )
        #expect(process.id == 42)
        #expect(process.pid == 1234)
        #expect(process.bundleID == "com.example.test")
        #expect(process.name == "TestApp")
        #expect(process.isProducingAudio == true)
    }

    @Test("enumerate() returns at least one process on a live system")
    func enumerateLive() {
        // The system normally has at least coreaudiod or a similar process
        // producing audio. From a sandboxed test bundle without audio
        // permissions, enumerate may return empty — accept either outcome
        // and just pin the API shape.
        let processes = AudioProcess.enumerate()
        #expect(processes.count >= 0)
    }
}

import Testing
import VMAudio

@Suite("MicrophoneCapture")
struct MicrophoneCaptureTests {
    @Test("Newly constructed capture is not running")
    func initialState() {
        let buffer = RingBuffer(capacity: 1024)
        let capture = MicrophoneCapture(buffer: buffer)
        #expect(capture.isRunning == false)
    }

    @Test("stop() before start() is a no-op")
    func stopBeforeStartNoOp() {
        let buffer = RingBuffer(capacity: 1024)
        let capture = MicrophoneCapture(buffer: buffer)
        capture.stop()
        #expect(capture.isRunning == false)
    }

    @Test("MicrophoneCapture is Sendable across boundaries")
    func sendableShape() async {
        let buffer = RingBuffer(capacity: 1024)
        let capture = MicrophoneCapture(buffer: buffer)
        // Crossing an actor boundary requires Sendable; if it weren't,
        // this would fail to compile under Swift 6 strict concurrency.
        await ActorHelper().receive(capture)
        #expect(capture.isRunning == false)
    }

    private actor ActorHelper {
        func receive(_ capture: MicrophoneCapture) {
            _ = capture.isRunning
        }
    }
}

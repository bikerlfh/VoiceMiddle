import Testing
import VMPipeline

@Suite("SessionController")
struct SessionControllerTests {
    @Test("Initial state is idle")
    func initialState() async {
        let controller = SessionController()
        let state = await controller.state
        #expect(state == .idle)
    }

    @Test("start transitions idle → active and stop transitions back to idle")
    func startStop() async {
        let controller = SessionController()
        await controller.start()
        #expect(await controller.state == .active)
        await controller.stop()
        #expect(await controller.state == .idle)
    }

    @Test("start while active is a no-op")
    func startWhileActiveIsNoOp() async {
        let controller = SessionController()
        await controller.start()
        await controller.start()
        #expect(await controller.state == .active)
    }

    @Test("stop while idle is a no-op")
    func stopWhileIdleIsNoOp() async {
        let controller = SessionController()
        await controller.stop()
        #expect(await controller.state == .idle)
    }

    @Test("Subscribers receive every state transition in order")
    func statesStream() async throws {
        let controller = SessionController()
        let stream = await controller.states

        let consumer = Task {
            var observed: [SessionController.State] = []
            for await state in stream {
                observed.append(state)
                if observed.count == 5 { break }
            }
            return observed
        }

        // Give the consumer a tick to subscribe.
        await Task.yield()

        await controller.start()
        await controller.stop()

        let observed = await consumer.value
        #expect(observed == [.idle, .starting, .active, .stopping, .idle])
    }
}

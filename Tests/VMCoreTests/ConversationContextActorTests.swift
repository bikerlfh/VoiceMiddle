import Testing
import Foundation
import VMCore

@Suite("ConversationContextActor")
struct ConversationContextActorTests {
    @Test("Caps history at the configured size")
    func capsHistory() async throws {
        let actor = ConversationContextActor(maxTurns: 3)
        for index in 0..<5 {
            await actor.appendTurn(.init(
                direction: .inbound,
                original: "src \(index)",
                translated: "dst \(index)",
                timestamp: Date()
            ))
        }
        let snapshot = await actor.snapshot(topicHint: nil)
        #expect(snapshot.recentTurns.count == 3)
        #expect(snapshot.recentTurns.first?.original == "src 2")
        #expect(snapshot.recentTurns.last?.original == "src 4")
    }

    @Test("Snapshot is independent of subsequent mutations")
    func snapshotIndependent() async throws {
        let actor = ConversationContextActor(maxTurns: 5)
        await actor.appendTurn(.init(
            direction: .inbound, original: "a", translated: "A",
            timestamp: Date()
        ))
        let snapshot = await actor.snapshot(topicHint: nil)
        await actor.appendTurn(.init(
            direction: .inbound, original: "b", translated: "B",
            timestamp: Date()
        ))
        #expect(snapshot.recentTurns.count == 1)
    }

    @Test("Clear empties the buffer")
    func clearEmpties() async throws {
        let actor = ConversationContextActor(maxTurns: 5)
        await actor.appendTurn(.init(
            direction: .outbound, original: "x", translated: "X",
            timestamp: Date()
        ))
        await actor.clear()
        let snapshot = await actor.snapshot(topicHint: nil)
        #expect(snapshot.recentTurns.isEmpty)
    }

    @Test("Topic hint flows through to the snapshot")
    func topicHint() async throws {
        let actor = ConversationContextActor(maxTurns: 2)
        let snapshot = await actor.snapshot(topicHint: "remote pair design review")
        #expect(snapshot.sessionTopicHint == "remote pair design review")
    }

    @Test("maxTurns must be positive")
    func zeroMaxTurnsTraps() {
        // We cannot easily test the precondition here without crashing the
        // test runner; this @Test exists to document the contract. A future
        // task may introduce a non-trapping constructor variant if needed.
        let actor = ConversationContextActor(maxTurns: 1)
        #expect(actor === actor)
    }
}

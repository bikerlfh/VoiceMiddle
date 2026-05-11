import Foundation
import VMCore

/// Top-level lifecycle controller for the user's translation session.
///
/// Owns the four-state transition machine (``State``) and a broadcast
/// ``AsyncStream`` that UI observers (menu bar item, HUD, settings) subscribe
/// to. Real pipeline orchestration is layered on top in later tasks; this
/// controller just owns the canonical lifecycle.
public actor SessionController {
    public enum State: String, Hashable, CaseIterable, Sendable {
        case idle
        case starting
        case active
        case stopping
    }

    public private(set) var state: State = .idle

    private var continuations: [UUID: AsyncStream<State>.Continuation] = [:]

    public init() {}

    /// Broadcast stream of state transitions. Each subscriber gets an
    /// independent stream that starts with the current state and then emits
    /// every subsequent transition until the subscriber cancels.
    ///
    /// Multiple subscribers are supported; each one receives the same
    /// sequence.
    public var states: AsyncStream<State> {
        AsyncStream { continuation in
            let id = UUID()
            continuation.yield(self.state)
            self.continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id: id) }
            }
        }
    }

    /// Begin a session. No-op if already starting or active.
    public func start() async {
        guard state == .idle else { return }
        transition(to: .starting)
        // Real wiring lands in later tasks; the starting state is currently
        // immediately followed by .active so the menu bar item reflects a
        // running session for manual testing.
        transition(to: .active)
    }

    /// End a session. No-op if already stopping or idle.
    public func stop() async {
        guard state == .active else { return }
        transition(to: .stopping)
        transition(to: .idle)
    }

    // MARK: - Internal helpers

    private func transition(to next: State) {
        state = next
        for continuation in continuations.values {
            continuation.yield(next)
        }
    }

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }
}

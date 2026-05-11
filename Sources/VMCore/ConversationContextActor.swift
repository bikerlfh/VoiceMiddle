/// Thread-safe rolling buffer of conversation turns shared by both
/// translation pipelines.
///
/// Each pipeline appends a ``ConversationContext/Turn`` after a successful
/// translation; both pipelines read a snapshot before each translation
/// request. The actor is the single source of truth, so the order of
/// appends across pipelines reflects real-time progression of the
/// conversation.
///
/// Snapshots are values: they do not change after they are taken, even if
/// the actor continues to accept new turns.
public actor ConversationContextActor {
    private var turns: [ConversationContext.Turn] = []
    private let maxTurns: Int

    /// - Parameter maxTurns: How many recent turns to retain. Must be > 0.
    public init(maxTurns: Int = 6) {
        precondition(maxTurns > 0, "maxTurns must be positive")
        self.maxTurns = maxTurns
    }

    /// Appends a turn and trims the buffer to `maxTurns`.
    public func appendTurn(_ turn: ConversationContext.Turn) {
        turns.append(turn)
        if turns.count > maxTurns {
            turns.removeFirst(turns.count - maxTurns)
        }
    }

    /// Returns an immutable snapshot of the current buffer.
    ///
    /// - Parameter topicHint: Optional session-level topic hint to embed in
    ///   the returned context.
    public func snapshot(topicHint: String?) -> ConversationContext {
        ConversationContext(recentTurns: turns, sessionTopicHint: topicHint)
    }

    /// Empties the buffer, e.g. when starting a new session.
    public func clear() {
        turns.removeAll(keepingCapacity: true)
    }
}

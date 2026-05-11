import Foundation

/// Snapshot of recent conversation history shared between translation
/// pipelines, used by context-aware translators to improve coherence across
/// turns.
///
/// `ConversationContext` is an immutable value type. It is produced by
/// ``ConversationContextActor/snapshot(topicHint:)`` and consumed by
/// translator implementations. Because it is a value, capturing it in an
/// in-flight translation request is safe even if the underlying actor
/// continues to append new turns.
public struct ConversationContext: Hashable, Sendable {
    /// A single completed turn from either direction.
    public struct Turn: Hashable, Sendable {
        public let direction: Direction
        public let original: String
        public let translated: String
        public let timestamp: Date

        public init(
            direction: Direction,
            original: String,
            translated: String,
            timestamp: Date
        ) {
            self.direction = direction
            self.original = original
            self.translated = translated
            self.timestamp = timestamp
        }
    }

    /// Recent turns ordered from oldest to newest. Capped at the actor's
    /// configured `maxTurns`.
    public let recentTurns: [Turn]

    /// Optional free-form hint about the session topic (e.g. "engineering
    /// interview about Swift concurrency"). Forwarded to the translator's
    /// system prompt where supported.
    public let sessionTopicHint: String?

    public init(recentTurns: [Turn], sessionTopicHint: String?) {
        self.recentTurns = recentTurns
        self.sessionTopicHint = sessionTopicHint
    }
}

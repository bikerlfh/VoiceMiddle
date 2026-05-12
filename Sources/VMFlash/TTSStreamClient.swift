import Foundation
import VMCore

/// Streaming text-to-speech client.
///
/// Implementations open a persistent transport, synthesize the provided text,
/// and emit PCM audio chunks via the configured sink. Synthesis is one-shot
/// per call: each ``synthesize(_:voice:sink:)`` invocation opens a fresh
/// session, streams the result, and closes.
public protocol TTSStreamClient: Sendable {
    /// Synthesizes `text` using `voice`.
    ///
    /// Audio is delivered as a sequence of `Data` chunks of 48 kHz / mono /
    /// Float32 PCM. `sink` is called from a Swift Concurrency context; it
    /// should not block.
    func synthesize(
        _ text: String,
        voice: VoiceID,
        sink: @escaping @Sendable (Data) -> Void
    ) async throws
}

public enum TTSError: Error, Hashable, Sendable {
    case empty
    case transport(message: String)
    case server(message: String)
    case decode
}

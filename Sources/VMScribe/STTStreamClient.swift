@preconcurrency import AVFoundation

/// Realtime speech-to-text stream client.
///
/// Implementations open a persistent transport (typically a WebSocket). The
/// caller pushes PCM frames as they arrive from the audio engine; partial and
/// final transcripts flow back asynchronously through ``partials`` and
/// ``finals``.
///
/// All implementations must be safe to call from a single task per direction
/// (the audio capture task pushes frames, the pipeline consumes transcripts);
/// they need not be re-entrant from multiple concurrent producers.
public protocol STTStreamClient: Sendable {
    /// Partial transcripts emitted while the speaker is still talking. Each
    /// value is the most recent best guess for the in-flight utterance, not a
    /// delta.
    var partials: AsyncStream<String> { get }

    /// Final transcripts emitted after the upstream confirms an utterance.
    var finals: AsyncStream<String> { get }

    /// Streaming errors surfaced by the upstream (e.g. invalid auth, format
    /// rejected). Connection-level failures handled internally via reconnect
    /// do NOT appear here.
    var errors: AsyncStream<STTError> { get }

    /// Connects (or reconnects) the transport. Safe to call multiple times.
    func connect() async

    /// Pushes 48 kHz / mono / Float32 frames to the upstream. Returns when
    /// the bytes have been handed to the transport, not when they have been
    /// acknowledged.
    func send(_ pcm: AVAudioPCMBuffer) async

    /// Signals the end of an utterance so the upstream emits the final
    /// transcript.
    func flushUtterance() async

    /// Closes the underlying transport.
    func close() async
}

public enum STTError: Error, Sendable, Equatable {
    case server(message: String)
    case decode
    case transport(message: String)
}

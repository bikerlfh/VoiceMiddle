import Foundation

/// Destination for translated PCM audio produced by a ``TranslationPipeline``.
///
/// Implementations receive `Data` chunks of 48 kHz / mono / Float32 PCM. The
/// sink is called from a Swift Concurrency context and is expected to be
/// fast: any long-running work (writing to a virtual device, mixing) should
/// be enqueued without blocking the calling task.
public protocol AudioSink: Sendable {
    /// Receives a chunk of Float32 PCM at 48 kHz mono.
    func receive(_ pcm: Data) async
}

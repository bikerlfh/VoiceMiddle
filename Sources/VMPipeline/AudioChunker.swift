import Foundation
import VMAudio

/// Drains an audio ``RingBuffer`` in fixed-size frames, feeds them to a ``VAD``,
/// and emits each contiguous speech utterance as an ``[Float]`` value on
/// ``utterances``.
///
/// The chunker runs its own task. ``start()`` launches the drain loop;
/// ``stop()`` cancels it and finishes the ``utterances`` stream.
///
/// Each ``AudioChunker`` exposes a single broadcast stream that is created
/// when the chunker is initialized. Iterating ``utterances`` from multiple
/// tasks shares the same underlying buffered values; iterating after
/// ``stop()`` returns immediately because the stream is already finished.
///
/// The chunker is intended to be owned 1:1 by a translation pipeline. If the
/// ring buffer fills up faster than the chunker drains (because the consumer
/// is blocked), the writer side returns short writes and audio is lost —
/// that's the correct behaviour for a real-time path.
public actor AudioChunker {
    /// 10 ms frame at 48 kHz mono = 480 samples.
    public static let frameSampleCount = 480
    /// How long to sleep when the buffer holds less than one full frame.
    private static let emptyBufferPollNanos: UInt64 = 5_000_000  // 5 ms

    public nonisolated let utterances: AsyncStream<[Float]>

    private let utterancesContinuation: AsyncStream<[Float]>.Continuation
    private let input: RingBuffer
    private var vad: VAD
    private var task: Task<Void, Never>?
    private var currentUtterance: [Float] = []
    private var stopped: Bool = false

    public init(input: RingBuffer, vad: VAD = VAD()) {
        self.input = input
        self.vad = vad
        self.currentUtterance.reserveCapacity(48_000)  // 1 s headroom

        var continuation: AsyncStream<[Float]>.Continuation!
        self.utterances = AsyncStream(bufferingPolicy: .unbounded) {
            continuation = $0
        }
        self.utterancesContinuation = continuation
    }

    public func start() {
        guard task == nil, !stopped else { return }
        task = Task { [weak self] in
            await self?.drain()
        }
    }

    public func stop() {
        guard !stopped else { return }
        stopped = true
        task?.cancel()
        task = nil
        utterancesContinuation.finish()
    }

    // MARK: - Internals

    private func drain() async {
        var scratch = [Float](
            repeating: 0, count: Self.frameSampleCount
        )
        while !Task.isCancelled {
            let read = scratch.withUnsafeMutableBufferPointer { ptr -> Int in
                input.read(ptr.baseAddress!, count: ptr.count)
            }
            // Only process a full frame so the VAD's hangover math is stable.
            // Partial reads mean the buffer is below one frame; sleep and
            // retry. The unread samples remain in the buffer.
            guard read == Self.frameSampleCount else {
                do {
                    try await Task.sleep(
                        nanoseconds: Self.emptyBufferPollNanos
                    )
                } catch { break }
                continue
            }
            let event = scratch.withUnsafeBufferPointer {
                vad.process(frame: $0)
            }
            switch event {
            case .speechStarted:
                currentUtterance.removeAll(keepingCapacity: true)
                currentUtterance.append(contentsOf: scratch)
            case .continued:
                if vad.isActive {
                    currentUtterance.append(contentsOf: scratch)
                }
            case .speechEnded:
                currentUtterance.append(contentsOf: scratch)
                let finished = currentUtterance
                currentUtterance.removeAll(keepingCapacity: true)
                utterancesContinuation.yield(finished)
            }
        }
    }
}

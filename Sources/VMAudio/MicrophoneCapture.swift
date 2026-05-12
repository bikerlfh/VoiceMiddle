import AVFoundation
import VMCore

/// Captures audio from the system default microphone at 48 kHz / mono /
/// Float32 and writes samples into the provided ``RingBuffer``.
///
/// Construction is cheap and does not touch any audio hardware. Call
/// ``start()`` to begin capture; samples then flow into the ring buffer from
/// the `AVAudioEngine` render thread until ``stop()`` is called.
///
/// **Thread safety.** Operations on the engine itself (start, stop, install
/// tap) are not thread-safe and must be invoked from a single thread; the
/// class is therefore intended to be owned by one orchestrator. The mutable
/// `_isRunning` flag is wrapped in a lock for safe read-only access from
/// other threads via ``isRunning``.
///
/// **Permissions.** macOS requires `NSMicrophoneUsageDescription` in the
/// app's Info.plist and that the user grant microphone access. The first
/// call to ``start()`` may trigger the system permission prompt.
public final class MicrophoneCapture: @unchecked Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        /// The system rejected the requested format. Includes the description
        /// returned by AVAudioEngine for diagnosis.
        case unsupportedFormat(description: String)
        /// `AVAudioEngine.start()` threw. Includes the underlying message.
        case engineStart(message: String)
    }

    public var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isRunning
    }

    private let engine = AVAudioEngine()
    private let buffer: RingBuffer
    private let lock = NSLock()
    private var _isRunning = false

    public init(buffer: RingBuffer) {
        self.buffer = buffer
    }

    /// Begins capture. Throws if the configured format cannot be produced by
    /// the input node or if the engine fails to start.
    public func start() throws {
        lock.lock(); defer { lock.unlock() }
        guard !_isRunning else { return }

        let input = engine.inputNode
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: CanonicalAudioFormat.sampleRate,
            channels: CanonicalAudioFormat.channelCount
        ) else {
            throw Error.unsupportedFormat(
                description: "Could not construct AVAudioFormat for "
                    + "\(CanonicalAudioFormat.sampleRate) Hz mono Float32"
            )
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) {
            [weak self] pcm, _ in
            guard let self,
                  let channels = pcm.floatChannelData else { return }
            _ = self.buffer.write(channels[0], count: Int(pcm.frameLength))
        }

        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw Error.engineStart(message: error.localizedDescription)
        }
        _isRunning = true
    }

    /// Stops capture. Safe to call when not running.
    public func stop() {
        lock.lock(); defer { lock.unlock() }
        guard _isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        _isRunning = false
    }
}

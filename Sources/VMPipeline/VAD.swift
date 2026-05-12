import Foundation

/// Energy + zero-crossing-rate voice activity detector for 48 kHz mono Float32
/// audio frames.
///
/// The VAD is a mutable value type: it tracks the current speech state and
/// the hangover countdown internally. Callers feed 10 ms frames (480 samples
/// at 48 kHz) and consume the emitted ``Event``.
///
/// Two thresholds gate the active state:
/// - **Energy** (root-mean-square over the frame) above ``energyThreshold``.
/// - **Zero-crossing rate** (proportion of sample pairs with opposite signs)
///   above ``zeroCrossingThreshold``. ZCR helps reject DC offset and very
///   low-frequency hum.
///
/// After speech ends, the hangover keeps the state ``active`` for
/// ``hangoverMs`` milliseconds of silence before emitting ``speechEnded``.
public struct VAD: Hashable, Sendable {
    public enum Event: Hashable, Sendable {
        case continued
        case speechStarted
        case speechEnded
    }

    public let sampleRate: Double
    public let energyThreshold: Float
    public let zeroCrossingThreshold: Float
    public let hangoverMs: Int

    /// Internal state. Public read for diagnostics; mutations happen only
    /// inside ``process(frame:)``.
    public private(set) var isActive: Bool = false

    /// Frames remaining in the hangover countdown. When 0 and the current
    /// frame is silent and ``isActive`` is true, ``speechEnded`` fires.
    private var hangoverFramesRemaining: Int = 0

    public init(
        sampleRate: Double = 48_000,
        energyThreshold: Float = 0.005,
        zeroCrossingThreshold: Float = 0.01,
        hangoverMs: Int = 600
    ) {
        precondition(sampleRate > 0)
        precondition(hangoverMs >= 0)
        self.sampleRate = sampleRate
        self.energyThreshold = energyThreshold
        self.zeroCrossingThreshold = zeroCrossingThreshold
        self.hangoverMs = hangoverMs
    }

    /// Processes one frame of audio. Returns the state transition triggered
    /// by the frame.
    ///
    /// The frame's expected length is `sampleRate * 0.010` samples (480 at
    /// 48 kHz) — this is not enforced; passing shorter or longer frames
    /// rescales the hangover-per-frame math accordingly.
    @discardableResult
    public mutating func process(
        frame: UnsafeBufferPointer<Float>
    ) -> Event {
        let frameMs = Int((Double(frame.count) / sampleRate) * 1000)
        let isFrameSpeech = isSpeech(frame: frame)

        if isFrameSpeech {
            hangoverFramesRemaining = framesForHangover(frameMs: frameMs)
            if !isActive {
                isActive = true
                return .speechStarted
            }
            return .continued
        }

        guard isActive else { return .continued }

        if hangoverFramesRemaining > 0 {
            hangoverFramesRemaining -= 1
            return .continued
        }

        isActive = false
        return .speechEnded
    }

    // MARK: - Internals

    private func isSpeech(frame: UnsafeBufferPointer<Float>) -> Bool {
        guard !frame.isEmpty else { return false }
        var energySumSquared: Float = 0
        var zeroCrossings: Int = 0
        var previousSign: FloatingPointSign? = nil
        for sample in frame {
            energySumSquared += sample * sample
            // Use copysign-based sign so 0 doesn't artificially flip.
            if sample == 0 { continue }
            let sign = sample.sign
            if let previous = previousSign, previous != sign {
                zeroCrossings += 1
            }
            previousSign = sign
        }
        let rms = (energySumSquared / Float(frame.count)).squareRoot()
        let zcr = Float(zeroCrossings) / Float(frame.count)
        return rms > energyThreshold && zcr > zeroCrossingThreshold
    }

    private func framesForHangover(frameMs: Int) -> Int {
        guard frameMs > 0 else { return 0 }
        // Round up so a partial frame still counts.
        return (hangoverMs + frameMs - 1) / frameMs
    }
}

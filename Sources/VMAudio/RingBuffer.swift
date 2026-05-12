import Atomics

/// Single-producer single-consumer lock-free ring buffer of `Float` samples.
///
/// Designed to shuttle PCM frames from a real-time audio callback (Core Audio
/// I/O proc or `AVAudioEngine` render thread) to a Swift Concurrency consumer
/// task.
///
/// **Concurrency contract.** Exactly one thread may call ``write(_:count:)``
/// at any time; exactly one (possibly different) thread may call
/// ``read(_:count:)`` at any time. The two operations are wait-free and never
/// allocate after construction.
///
/// **Behaviour.** Writes that don't fit return the number of samples actually
/// written (no overwrite of unread data). Reads from an empty buffer return
/// zero (no blocking). Capacity is rounded up to the next power of two so the
/// modulo arithmetic can use a bitmask.
public final class RingBuffer: @unchecked Sendable {
    private let storage: UnsafeMutableBufferPointer<Float>
    private let mask: Int
    private let head: ManagedAtomic<Int>    // next write index, monotonically increasing
    private let tail: ManagedAtomic<Int>    // next read index, monotonically increasing
    /// EMA of RMS level over recent writes, in [0, 1]. Stored as the bit
    /// pattern of a `Float` so we can update atomically without a lock.
    private let levelBits: ManagedAtomic<UInt32>
    private static let levelEMAAlpha: Float = 0.3

    /// - Parameter capacity: Minimum requested capacity in samples. The
    ///   actual capacity is rounded up to the next power of two and must be
    ///   at least 2.
    public init(capacity: Int) {
        let rounded = Swift.max(2, capacity.nextPowerOfTwo)
        let base = UnsafeMutablePointer<Float>.allocate(capacity: rounded)
        base.initialize(repeating: 0, count: rounded)
        self.storage = UnsafeMutableBufferPointer(start: base, count: rounded)
        self.mask = rounded - 1
        self.head = ManagedAtomic<Int>(0)
        self.tail = ManagedAtomic<Int>(0)
        self.levelBits = ManagedAtomic<UInt32>(Float(0).bitPattern)
    }

    deinit {
        if let base = storage.baseAddress {
            base.deinitialize(count: storage.count)
            base.deallocate()
        }
    }

    /// Writes up to `count` samples starting at `source`. Returns the number
    /// of samples actually written, which may be less than `count` when the
    /// buffer is near-full.
    ///
    /// Safe to call from a real-time audio thread.
    @discardableResult
    public func write(_ source: UnsafePointer<Float>, count: Int) -> Int {
        precondition(count >= 0)
        let head = self.head.load(ordering: .relaxed)
        let tail = self.tail.load(ordering: .acquiring)
        let free = storage.count - (head &- tail)
        let n = Swift.min(count, free)
        var energy: Float = 0
        for index in 0..<n {
            let sample = source[index]
            storage[(head &+ index) & mask] = sample
            energy += sample * sample
        }
        self.head.store(head &+ n, ordering: .releasing)
        if n > 0 {
            let rms = (energy / Float(n)).squareRoot()
            let previous = Float(
                bitPattern: levelBits.load(ordering: .relaxed)
            )
            let next = previous * (1 - Self.levelEMAAlpha)
                + rms * Self.levelEMAAlpha
            levelBits.store(
                next.bitPattern, ordering: .relaxed
            )
        }
        return n
    }

    /// Reads up to `count` samples into `destination`. Returns the number of
    /// samples actually read, which may be less than `count` when the buffer
    /// holds fewer pending samples.
    ///
    /// Safe to call from a real-time audio thread.
    @discardableResult
    public func read(
        _ destination: UnsafeMutablePointer<Float>,
        count: Int
    ) -> Int {
        precondition(count >= 0)
        let tail = self.tail.load(ordering: .relaxed)
        let head = self.head.load(ordering: .acquiring)
        let available = head &- tail
        let n = Swift.min(count, available)
        for index in 0..<n {
            destination[index] = storage[(tail &+ index) & mask]
        }
        self.tail.store(tail &+ n, ordering: .releasing)
        return n
    }

    /// Snapshot of the number of samples currently pending. May be slightly
    /// stale under concurrent updates; intended for diagnostics, never for
    /// flow-control decisions.
    public var approximateCount: Int {
        head.load(ordering: .relaxed) &- tail.load(ordering: .relaxed)
    }

    /// Exponentially-weighted RMS level of recent writes, in `[0, 1]`.
    /// Updates on every ``write(_:count:)`` call; safe to read from any
    /// thread. Intended for diagnostic VU meters, not for flow control.
    public var currentLevel: Float {
        Float(bitPattern: levelBits.load(ordering: .relaxed))
    }
}

private extension Int {
    /// Smallest power of two greater than or equal to `self`, for `self >= 1`.
    var nextPowerOfTwo: Int {
        guard self > 1 else { return 1 }
        return 1 << (Int.bitWidth - (self - 1).leadingZeroBitCount)
    }
}

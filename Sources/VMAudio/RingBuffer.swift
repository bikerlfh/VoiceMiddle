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
        for index in 0..<n {
            storage[(head &+ index) & mask] = source[index]
        }
        self.head.store(head &+ n, ordering: .releasing)
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
}

private extension Int {
    /// Smallest power of two greater than or equal to `self`, for `self >= 1`.
    var nextPowerOfTwo: Int {
        guard self > 1 else { return 1 }
        return 1 << (Int.bitWidth - (self - 1).leadingZeroBitCount)
    }
}

import Testing
import VMAudio

@Suite("RingBuffer")
struct RingBufferTests {
    @Test("Write then read recovers all samples in order")
    func writeRead() {
        let buffer = RingBuffer(capacity: 1024)
        let input: [Float] = (0..<256).map(Float.init)
        let written = input.withUnsafeBufferPointer {
            buffer.write($0.baseAddress!, count: $0.count)
        }
        #expect(written == 256)

        var output = [Float](repeating: 0, count: 256)
        let read = output.withUnsafeMutableBufferPointer {
            buffer.read($0.baseAddress!, count: $0.count)
        }
        #expect(read == 256)
        #expect(output == input)
    }

    @Test("Write past capacity writes only what fits")
    func overflowRefused() {
        let buffer = RingBuffer(capacity: 4)
        let input: [Float] = [1, 2, 3, 4, 5]
        let written = input.withUnsafeBufferPointer {
            buffer.write($0.baseAddress!, count: $0.count)
        }
        // Capacity rounds up to the next power of two (4 -> 4 since already
        // a power of two); the buffer can hold up to `capacity` samples
        // before the writer must wait for the reader.
        #expect(written == 4)
    }

    @Test("Read from empty buffer returns zero")
    func emptyRead() {
        let buffer = RingBuffer(capacity: 16)
        var output = [Float](repeating: -1, count: 8)
        let read = output.withUnsafeMutableBufferPointer {
            buffer.read($0.baseAddress!, count: $0.count)
        }
        #expect(read == 0)
        // Output buffer should not have been written to.
        #expect(output == [Float](repeating: -1, count: 8))
    }

    @Test("Wrap-around preserves order across the boundary")
    func wrapAround() {
        let buffer = RingBuffer(capacity: 8)
        // First fill near the end.
        let first: [Float] = [1, 2, 3, 4, 5, 6]
        _ = first.withUnsafeBufferPointer {
            buffer.write($0.baseAddress!, count: $0.count)
        }
        // Drain a few.
        var drain = [Float](repeating: 0, count: 4)
        _ = drain.withUnsafeMutableBufferPointer {
            buffer.read($0.baseAddress!, count: $0.count)
        }
        #expect(drain == [1, 2, 3, 4])
        // Write more so the producer wraps the head past the end.
        let second: [Float] = [7, 8, 9, 10]
        let written = second.withUnsafeBufferPointer {
            buffer.write($0.baseAddress!, count: $0.count)
        }
        #expect(written == 4)
        // Read everything still in the buffer.
        var out = [Float](repeating: 0, count: 6)
        let read = out.withUnsafeMutableBufferPointer {
            buffer.read($0.baseAddress!, count: $0.count)
        }
        #expect(read == 6)
        #expect(out == [5, 6, 7, 8, 9, 10])
    }

    @Test("Capacity rounds up to the next power of two")
    func capacityRounding() {
        let buffer = RingBuffer(capacity: 10)
        let input = [Float](repeating: 0.5, count: 16)
        let written = input.withUnsafeBufferPointer {
            buffer.write($0.baseAddress!, count: $0.count)
        }
        #expect(written == 16)
    }

    @Test("approximateCount reflects pending samples")
    func approximateCount() {
        let buffer = RingBuffer(capacity: 16)
        #expect(buffer.approximateCount == 0)
        let input: [Float] = [1, 2, 3]
        _ = input.withUnsafeBufferPointer {
            buffer.write($0.baseAddress!, count: $0.count)
        }
        #expect(buffer.approximateCount == 3)
        var drain = [Float](repeating: 0, count: 3)
        _ = drain.withUnsafeMutableBufferPointer {
            buffer.read($0.baseAddress!, count: $0.count)
        }
        #expect(buffer.approximateCount == 0)
    }

    @Test("Single-producer single-consumer roundtrip across tasks")
    func spscAcrossTasks() async {
        let buffer = RingBuffer(capacity: 1024)
        let total = 8192

        async let producer: Void = {
            var written = 0
            while written < total {
                let chunk: [Float] = (0..<32).map { Float(written + $0) }
                var attempted = 0
                while attempted < chunk.count {
                    let n = chunk.withUnsafeBufferPointer {
                        buffer.write(
                            $0.baseAddress!.advanced(by: attempted),
                            count: chunk.count - attempted
                        )
                    }
                    attempted += n
                    if n == 0 { await Task.yield() }
                }
                written += chunk.count
            }
        }()

        async let consumer: [Float] = {
            var output = [Float]()
            output.reserveCapacity(total)
            var scratch = [Float](repeating: 0, count: 64)
            while output.count < total {
                let n = scratch.withUnsafeMutableBufferPointer {
                    buffer.read($0.baseAddress!, count: $0.count)
                }
                if n == 0 {
                    await Task.yield()
                    continue
                }
                output.append(contentsOf: scratch[..<n])
            }
            return output
        }()

        _ = await producer
        let result = await consumer
        #expect(result.count == total)
        #expect(result == (0..<total).map { Float($0) })
    }
}

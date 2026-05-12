import CoreAudio
import Foundation
import VMCore

/// Captures audio output from a target process via Core Audio Process Taps
/// (macOS 14.4+) and writes 48 kHz / mono / Float32 samples into the provided
/// ``RingBuffer``.
///
/// **Implementation status — scaffold only.** ``start()`` currently throws
/// ``Error/notImplemented`` and ``stop()`` is a no-op. The full Core Audio
/// call chain lands in Task 2.13, when we can iterate against a live audio
/// source end-to-end. The intended sequence, preserved here for reference:
///
/// 1. Build a `CATapDescription` whitelisting the target PID (mono mixdown).
/// 2. `AudioHardwareCreateProcessTap` to materialize the tap.
/// 3. `AudioHardwareCreateAggregateDevice` to wrap the tap in a device that
///    can be opened via standard Core Audio APIs.
/// 4. Install an `AudioDeviceIOProc` that reads the tap's mixed stream and
///    writes Float32 samples into the ring buffer.
/// 5. `AudioDeviceStart` begins delivery; ``stop()`` reverses the chain
///    (stop device, remove IOProc, destroy aggregate device, destroy tap).
///
/// **Permissions.** Requires the app's Info.plist to declare
/// `NSAudioCaptureUsageDescription`. The first call to ``start()`` (once
/// implemented) will trigger the system permission prompt.
///
/// This type cannot be exercised without a live audio system; tests pin the
/// API shape only.
public actor AppAudioCapture {
    public enum Error: Swift.Error, Hashable, Sendable {
        /// The scaffold's ``AppAudioCapture/start()`` was invoked before the
        /// full Core Audio wiring lands in Task 2.13.
        case notImplemented
        /// `AudioHardwareCreateProcessTap` failed with the given OSStatus.
        case tapCreationFailed(status: OSStatus)
        /// `AudioHardwareCreateAggregateDevice` failed with the given
        /// OSStatus.
        case aggregateCreationFailed(status: OSStatus)
        /// `AudioDeviceCreateIOProcID` failed with the given OSStatus.
        case ioProcInstallFailed(status: OSStatus)
        /// `AudioDeviceStart` failed with the given OSStatus.
        case deviceStartFailed(status: OSStatus)
    }

    public let process: AudioProcess
    public private(set) var isRunning: Bool = false

    private let buffer: RingBuffer
    private var tapID: AudioObjectID = .zero
    private var aggregateID: AudioObjectID = .zero
    private var ioProcID: AudioDeviceIOProcID?

    public init(process: AudioProcess, buffer: RingBuffer) {
        self.process = process
        self.buffer = buffer
    }

    /// Begins capture. **Currently throws ``Error/notImplemented``** — the
    /// full Core Audio Process Taps wiring lands in Task 2.13. See the type
    /// doc comment for the intended call sequence.
    public func start() throws {
        throw Error.notImplemented
    }

    /// Tears down the tap and aggregate device. Safe to call when not
    /// running. **Currently a no-op** — paired with the deferred ``start()``
    /// implementation.
    public func stop() {
        // Intended teardown order (Task 2.13):
        //   1. AudioDeviceStop(aggregateID, ioProcID)
        //   2. AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        //   3. AudioHardwareDestroyAggregateDevice(aggregateID)
        //   4. AudioHardwareDestroyProcessTap(tapID)
        isRunning = false
    }
}

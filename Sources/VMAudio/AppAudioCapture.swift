import CoreAudio
import Foundation
import VMCore

/// Captures audio output from a target process via Core Audio Process Taps
/// (macOS 14.2+) and writes 48 kHz / mono / Float32 samples into the provided
/// ``RingBuffer``.
///
/// The capture chain is:
/// 1. Build a `CATapDescription` (mono mixdown) whitelisting the target
///    process's `AudioObjectID`.
/// 2. `AudioHardwareCreateProcessTap` materializes the tap and returns its
///    `AudioObjectID`. The tap's persistent UID is then read via
///    `kAudioTapPropertyUID` so we can refer to it from the aggregate
///    device composition.
/// 3. `AudioHardwareCreateAggregateDevice` wraps the tap in a private
///    aggregate device so the tap can be opened via standard
///    `AudioDeviceIOProc` machinery.
/// 4. `AudioDeviceCreateIOProcID` installs a `@convention(c)` IOProc that
///    copies the inbound channel-0 PCM into the caller-provided
///    ``RingBuffer``.
/// 5. `AudioDeviceStart` begins delivery; ``stop()`` reverses the chain.
///
/// **Permissions.** Requires the app's Info.plist to declare
/// `NSAudioCaptureUsageDescription`. The first call to ``start()`` will
/// trigger the system permission prompt.
///
/// This type is exercised manually against a live audio source; its inner
/// Core Audio calls cannot be unit-tested without `coreaudiod` access.
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
        /// Could not read the tap's UID via `kAudioTapPropertyUID`.
        case tapUIDUnavailable(status: OSStatus)
    }

    public let process: AudioProcess
    public private(set) var isRunning: Bool = false

    private let buffer: RingBuffer
    private var tapID: AudioObjectID = .zero
    private var aggregateID: AudioObjectID = .zero
    private var ioProcID: AudioDeviceIOProcID?
    /// Strong reference to the boxed ring-buffer pointer handed to the
    /// IOProc through `clientData`. We retain it as `Unmanaged` for the
    /// lifetime of the IOProc and release it in ``stop()``.
    private var bufferRetained: Unmanaged<RingBuffer>?

    public init(process: AudioProcess, buffer: RingBuffer) {
        self.process = process
        self.buffer = buffer
    }

    /// Begins capture. Creates the tap, aggregate device, and IOProc, then
    /// calls `AudioDeviceStart`. Idempotent; calling ``start()`` while
    /// already running is a no-op.
    public func start() throws {
        guard !isRunning else { return }

        // 1. Build the tap description for this PID. We use
        //    `initMonoMixdownOfProcesses` so the tap emits a single
        //    Float32 channel, matching CanonicalAudioFormat.
        let description = CATapDescription(
            monoMixdownOfProcesses: [process.id]
        )
        description.muteBehavior = .unmuted
        description.isPrivate = true
        description.isExclusive = false
        description.name = "VoiceMiddle tap \(process.pid)"

        // 2. Create the tap.
        var newTapID: AudioObjectID = .zero
        let tapStatus = AudioHardwareCreateProcessTap(
            description, &newTapID
        )
        guard tapStatus == noErr, newTapID != .zero else {
            throw Error.tapCreationFailed(status: tapStatus)
        }
        self.tapID = newTapID

        // Read the tap's persistent UID — required for the aggregate
        // device composition.
        let tapUID: String
        do {
            tapUID = try Self.readTapUID(tapID: newTapID)
        } catch {
            AudioHardwareDestroyProcessTap(newTapID)
            self.tapID = .zero
            throw error
        }

        // 3. Build the private aggregate device composition. The
        //    `kAudioAggregateDeviceTapListKey` array contains one
        //    sub-tap referencing our tap's UID.
        let aggregateUID = "com.luismo.voicemiddle.aggregate.\(UUID().uuidString)"
        let composition: [String: Any] = [
            kAudioAggregateDeviceNameKey:
                "VoiceMiddle Aggregate (\(process.name))",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: tapUID]
            ],
        ]
        var newAggregateID: AudioObjectID = .zero
        let aggStatus = AudioHardwareCreateAggregateDevice(
            composition as CFDictionary, &newAggregateID
        )
        guard aggStatus == noErr, newAggregateID != .zero else {
            AudioHardwareDestroyProcessTap(newTapID)
            self.tapID = .zero
            throw Error.aggregateCreationFailed(status: aggStatus)
        }
        self.aggregateID = newAggregateID

        // 4. Install the IOProc. We retain the `RingBuffer` through an
        //    `Unmanaged` pointer so the IOProc can resolve it without
        //    touching the Swift runtime's reference counting on the hot
        //    path.
        let retained = Unmanaged.passRetained(buffer)
        self.bufferRetained = retained
        let clientData = UnsafeMutableRawPointer(retained.toOpaque())
        var newIOProcID: AudioDeviceIOProcID?
        let ioStatus = AudioDeviceCreateIOProcID(
            newAggregateID, Self.ioProc, clientData, &newIOProcID
        )
        guard ioStatus == noErr, let installedIOProcID = newIOProcID else {
            retained.release()
            self.bufferRetained = nil
            AudioHardwareDestroyAggregateDevice(newAggregateID)
            self.aggregateID = .zero
            AudioHardwareDestroyProcessTap(newTapID)
            self.tapID = .zero
            throw Error.ioProcInstallFailed(status: ioStatus)
        }
        self.ioProcID = installedIOProcID

        // 5. Start the aggregate device.
        let startStatus = AudioDeviceStart(newAggregateID, installedIOProcID)
        guard startStatus == noErr else {
            AudioDeviceDestroyIOProcID(newAggregateID, installedIOProcID)
            self.ioProcID = nil
            retained.release()
            self.bufferRetained = nil
            AudioHardwareDestroyAggregateDevice(newAggregateID)
            self.aggregateID = .zero
            AudioHardwareDestroyProcessTap(newTapID)
            self.tapID = .zero
            throw Error.deviceStartFailed(status: startStatus)
        }

        isRunning = true
    }

    /// Tears down the IOProc, aggregate device, and tap. Safe to call when
    /// not running.
    public func stop() {
        guard isRunning else {
            // Even if start() failed partway, clean up any lingering state.
            if let retained = bufferRetained {
                retained.release()
                bufferRetained = nil
            }
            return
        }
        if let proc = ioProcID, aggregateID != .zero {
            AudioDeviceStop(aggregateID, proc)
            AudioDeviceDestroyIOProcID(aggregateID, proc)
        }
        ioProcID = nil
        if aggregateID != .zero {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = .zero
        }
        if tapID != .zero {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = .zero
        }
        if let retained = bufferRetained {
            retained.release()
            bufferRetained = nil
        }
        isRunning = false
    }

    // MARK: - Private helpers

    /// Reads `kAudioTapPropertyUID` for the freshly created tap.
    private static func readTapUID(tapID: AudioObjectID) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString?>.size)
        var cfString: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &cfString) { ptr in
            AudioObjectGetPropertyData(
                tapID, &address, 0, nil, &size, ptr
            )
        }
        guard status == noErr, let cf = cfString?.takeRetainedValue() else {
            throw Error.tapUIDUnavailable(status: status)
        }
        return cf as String
    }

    /// `@convention(c)` IOProc that copies channel-0 Float32 samples into
    /// the ring buffer. Must not allocate.
    private static let ioProc: AudioDeviceIOProc = {
        _, _, inInputData, _, _, _, clientData -> OSStatus in
        guard let opaque = clientData else { return noErr }
        let buffer = Unmanaged<RingBuffer>
            .fromOpaque(opaque)
            .takeUnretainedValue()
        let abl = inInputData.pointee
        guard abl.mNumberBuffers > 0 else { return noErr }
        // The aggregate-over-process-tap delivers one AudioBuffer per
        // tap channel; with a mono mixdown that's a single buffer at
        // index 0. AudioBufferList's `mBuffers` is a flexible array
        // member in C, so we step past the leading `mNumberBuffers`
        // field to reach buffer 0.
        let firstBufferPointer = UnsafeMutableRawPointer(
            mutating: inInputData
        )
        .advanced(by: MemoryLayout<UInt32>.size)
        .assumingMemoryBound(to: AudioBuffer.self)
        let firstBuffer = firstBufferPointer.pointee
        let frameCount = Int(firstBuffer.mDataByteSize)
            / MemoryLayout<Float>.size
        guard frameCount > 0,
              let bytes = firstBuffer.mData?
                .assumingMemoryBound(to: Float.self)
        else { return noErr }
        _ = buffer.write(bytes, count: frameCount)
        return noErr
    }
}

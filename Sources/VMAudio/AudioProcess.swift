import CoreAudio
import Foundation

/// Snapshot of a macOS process that owns or produces audio, as seen by Core
/// Audio's process registry (macOS 14.4+).
///
/// Discovered by walking `kAudioHardwarePropertyProcessObjectList` and reading
/// the per-process properties (`kAudioProcessPropertyPID`,
/// `kAudioProcessPropertyBundleID`, `kAudioProcessPropertyIsRunning`). Used as
/// the target descriptor for ``AppAudioCapture``.
public struct AudioProcess: Hashable, Sendable {
    /// Core Audio object ID for the process. Stable for the lifetime of the
    /// process within `coreaudiod`.
    public let id: AudioObjectID
    /// POSIX process ID, or `0` if Core Audio refused to report it.
    public let pid: pid_t
    /// Bundle identifier reported by Core Audio. `nil` for processes without
    /// a CFBundleIdentifier (e.g. command-line tools).
    public let bundleID: String?
    /// Human-readable name. Falls back to `"PID <pid>"` when no bundle ID is
    /// available.
    public let name: String
    /// True if the process is currently producing or receiving audio data,
    /// per `kAudioProcessPropertyIsRunning`.
    public let isProducingAudio: Bool

    public init(
        id: AudioObjectID,
        pid: pid_t,
        bundleID: String?,
        name: String,
        isProducingAudio: Bool
    ) {
        self.id = id
        self.pid = pid
        self.bundleID = bundleID
        self.name = name
        self.isProducingAudio = isProducingAudio
    }

    /// Enumerates all audio-producing processes known to Core Audio.
    ///
    /// Returns an empty array on failure (e.g. when the host lacks audio
    /// permission, or when running inside a sandboxed test bundle with no
    /// audio entitlement). Never throws.
    public static func enumerate() -> [AudioProcess] {
        let processIDs: [AudioObjectID]
        do {
            processIDs = try readProcessList()
        } catch {
            return []
        }
        return processIDs.compactMap { describe(processID: $0) }
    }

    // MARK: - Private helpers

    private static func readProcessList() throws -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &dataSize
        )
        guard sizeStatus == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain,
                          code: Int(sizeStatus))
        }
        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: count)
        let status = ids.withUnsafeMutableBufferPointer { ptr in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address, 0, nil, &dataSize, ptr.baseAddress!
            )
        }
        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain,
                          code: Int(status))
        }
        return ids
    }

    private static func describe(processID: AudioObjectID) -> AudioProcess? {
        let pid = readProperty(
            on: processID,
            selector: kAudioProcessPropertyPID,
            type: pid_t.self
        ) ?? 0
        let bundleID = readStringProperty(
            on: processID,
            selector: kAudioProcessPropertyBundleID
        )
        let name = bundleID ?? "PID \(pid)"
        let isProducing = (readProperty(
            on: processID,
            selector: kAudioProcessPropertyIsRunning,
            type: UInt32.self
        ) ?? 0) != 0
        return AudioProcess(
            id: processID,
            pid: pid,
            bundleID: bundleID,
            name: name,
            isProducingAudio: isProducing
        )
    }

    private static func readProperty<T>(
        on id: AudioObjectID,
        selector: AudioObjectPropertySelector,
        type: T.Type
    ) -> T? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        let status = AudioObjectGetPropertyData(
            id, &address, 0, nil, &size, value
        )
        guard status == noErr else { return nil }
        return value.pointee
    }

    private static func readStringProperty(
        on id: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            id, &address, 0, nil, &size
        ) == noErr else { return nil }
        var cfString: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &cfString) { ptr in
            AudioObjectGetPropertyData(
                id, &address, 0, nil, &size, ptr
            )
        }
        guard status == noErr,
              let cf = cfString?.takeRetainedValue()
        else { return nil }
        return cf as String
    }
}

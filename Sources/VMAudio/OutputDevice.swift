import CoreAudio
import Foundation

/// Snapshot of a Core Audio output device suitable for routing translated
/// outbound audio into. Built by walking
/// `kAudioHardwarePropertyDevices` and filtering to devices that expose at
/// least one output stream.
///
/// The struct is `Sendable` and `Hashable`; `id` is the Core Audio object id
/// (only stable within the running `coreaudiod`). `uid` is the persistent
/// device identifier reported by Core Audio (e.g. for `BlackHole 2ch`).
public struct OutputDevice: Hashable, Sendable {
    public let id: AudioObjectID
    public let name: String
    public let uid: String?

    public init(id: AudioObjectID, name: String, uid: String?) {
        self.id = id
        self.name = name
        self.uid = uid
    }

    /// Returns all Core Audio devices that expose at least one output stream,
    /// sorted by name. Returns an empty array on failure.
    public static func enumerate() -> [OutputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size
        ) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: count)
        let status = ids.withUnsafeMutableBufferPointer { ptr in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address, 0, nil, &size, ptr.baseAddress!
            )
        }
        guard status == noErr else { return [] }

        return ids.compactMap { describe(deviceID: $0) }
            .filter { $0.hasOutputStreams }
            .sorted { $0.name < $1.name }
    }

    /// First device whose name contains the substring (case-insensitive).
    public static func firstMatching(name pattern: String)
    -> OutputDevice? {
        enumerate().first {
            $0.name.range(
                of: pattern, options: .caseInsensitive
            ) != nil
        }
    }

    // MARK: - Private helpers

    private var hasOutputStreams: Bool {
        var streamsAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var streamsSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            id, &streamsAddress, 0, nil, &streamsSize
        )
        return status == noErr && streamsSize > 0
    }

    private static func describe(deviceID: AudioObjectID) -> OutputDevice? {
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            deviceID, &nameAddress, 0, nil, &size
        ) == noErr else { return nil }
        var cfName: Unmanaged<CFString>? = nil
        let nameStatus = withUnsafeMutablePointer(to: &cfName) { ptr in
            AudioObjectGetPropertyData(
                deviceID, &nameAddress, 0, nil, &size, ptr
            )
        }
        guard nameStatus == noErr,
              let name = cfName?.takeRetainedValue()
        else { return nil }

        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uidSize: UInt32 = 0
        var cfUID: Unmanaged<CFString>? = nil
        var uidString: String? = nil
        if AudioObjectGetPropertyDataSize(
            deviceID, &uidAddress, 0, nil, &uidSize
        ) == noErr {
            let uidStatus = withUnsafeMutablePointer(to: &cfUID) { ptr in
                AudioObjectGetPropertyData(
                    deviceID, &uidAddress, 0, nil, &uidSize, ptr
                )
            }
            if uidStatus == noErr {
                uidString = cfUID?.takeRetainedValue() as String?
            }
        }
        return OutputDevice(
            id: deviceID,
            name: name as String,
            uid: uidString
        )
    }
}

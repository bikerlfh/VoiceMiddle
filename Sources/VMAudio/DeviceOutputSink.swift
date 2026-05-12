@preconcurrency import AVFoundation
import CoreAudio
import Foundation
import VMCore

/// `AudioSink` that writes 48 kHz mono Float32 PCM into a specific Core Audio
/// output device identified by `AudioDeviceID`.
///
/// Used to route translated outbound audio into a virtual microphone device
/// such as BlackHole 2ch. The communication app (Teams, Meet, Slack, ...)
/// selects the same virtual device as its microphone input, so the other
/// party hears the user's translated voice.
///
/// Implementation note: `AVAudioEngine` doesn't expose direct output-device
/// selection through a Swift API on macOS. We reach down to the engine's
/// output node `AudioUnit` and set `kAudioOutputUnitProperty_CurrentDevice`
/// before any nodes are attached, mirroring the AUHAL pattern Apple
/// recommends for Core Audio routing.
public actor DeviceOutputSink {
    public enum Error: Swift.Error, Hashable, Sendable {
        /// The output node had no underlying `AudioUnit` to configure.
        case audioUnitUnavailable
        /// `AudioUnitSetProperty` rejected the device id.
        case deviceConfigurationFailed(status: OSStatus)
        /// `AVAudioEngine.start()` threw.
        case engineStartFailed(message: String)
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private var configuredDeviceID: AudioDeviceID = .zero
    private var started = false

    public init() {
        self.format = AVAudioFormat(
            standardFormatWithSampleRate:
                CanonicalAudioFormat.sampleRate,
            channels: CanonicalAudioFormat.channelCount
        )!
    }

    /// Targets the given Core Audio output device and starts playback.
    ///
    /// Safe to call repeatedly; subsequent calls are no-ops once started.
    public func start(deviceID: AudioDeviceID) throws {
        if started { return }
        configuredDeviceID = deviceID

        // Bind the engine's output AudioUnit to the target device BEFORE
        // attaching any nodes; AVAudioEngine reuses the same AU when it
        // starts up its render graph.
        guard let unit = engine.outputNode.audioUnit else {
            throw Error.audioUnitUnavailable
        }
        var id = deviceID
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw Error.deviceConfigurationFailed(status: status)
        }

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            engine.detach(player)
            throw Error.engineStartFailed(
                message: error.localizedDescription
            )
        }
        player.play()
        started = true
    }

    /// Stops playback. Safe to call when not started.
    public func stop() {
        guard started else { return }
        player.stop()
        engine.stop()
        engine.detach(player)
        started = false
    }

    /// True once `start(deviceID:)` has succeeded.
    public var isStarted: Bool { started }

    /// `AudioSink` conformance — schedules the chunk on the device player.
    public func receive(_ pcm: Data) {
        guard started else { return }
        guard let buffer = Self.pcmBuffer(from: pcm, format: format)
        else { return }
        player.scheduleBuffer(buffer, completionHandler: nil)
    }

    // MARK: - Buffer conversion

    private static func pcmBuffer(
        from data: Data, format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(
            data.count / MemoryLayout<Float>.size
        )
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: frameCount
              ),
              let channelData = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = frameCount
        data.withUnsafeBytes { raw in
            guard let source = raw.bindMemory(to: Float.self)
                .baseAddress else { return }
            channelData.update(
                from: source, count: Int(frameCount)
            )
        }
        return buffer
    }
}

extension DeviceOutputSink: AudioSink {}

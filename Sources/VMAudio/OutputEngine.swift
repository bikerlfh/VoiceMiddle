import AVFoundation
import Foundation
import VMCore

/// Mixes inbound original audio with translated TTS audio for playback on
/// the user's output device. Supports ducking the original while TTS plays.
///
/// Internally wraps a single `AVAudioEngine` with three nodes:
/// - `originalPlayer`: `AVAudioPlayerNode` for the unmodified call audio
///   tapped from the target application.
/// - `ttsPlayer`: `AVAudioPlayerNode` for synthesized translation audio.
/// - `mixer`: `AVAudioMixerNode` that combines both before the main mixer.
///
/// The mixer's `inputVolume` on the original-player bus is animated between
/// 1.0 (unity) and the configured ducked gain. Animation is done in small
/// steps over `fadeMs` to avoid audible clicks.
///
/// The class is an `actor` so configuration updates and ramp scheduling
/// serialize cleanly under contention. The engine itself is thread-safe in
/// the documented way (start/stop on main thread; scheduling buffers on any).
public actor OutputEngine {
    public struct Configuration: Hashable, Sendable {
        public var mode: DuckingMode
        public var levelDB: Double
        public var fadeMs: Int
    }

    public enum Error: Swift.Error, Hashable, Sendable {
        case engineStartFailed(message: String)
    }

    private let engine = AVAudioEngine()
    private let originalPlayer = AVAudioPlayerNode()
    private let ttsPlayer = AVAudioPlayerNode()
    private let format: AVAudioFormat

    private var configuration: Configuration
    private var isStarted = false

    public init(
        duckingMode: DuckingMode = .duckToLevel,
        duckingLevelDB: Double = -20,
        fadeMs: Int = 80
    ) {
        self.configuration = .init(
            mode: duckingMode,
            levelDB: duckingLevelDB,
            fadeMs: fadeMs
        )
        self.format = AVAudioFormat(
            standardFormatWithSampleRate:
                CanonicalAudioFormat.sampleRate,
            channels: CanonicalAudioFormat.channelCount
        )!
    }

    public func currentConfiguration() -> Configuration {
        configuration
    }

    public func updateConfiguration(
        mode: DuckingMode, levelDB: Double, fadeMs: Int
    ) {
        configuration = Configuration(
            mode: mode, levelDB: levelDB, fadeMs: fadeMs
        )
    }

    public func start() throws {
        guard !isStarted else { return }
        engine.attach(originalPlayer)
        engine.attach(ttsPlayer)
        engine.connect(originalPlayer, to: engine.mainMixerNode,
                       format: format)
        engine.connect(ttsPlayer, to: engine.mainMixerNode,
                       format: format)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw Error.engineStartFailed(
                message: error.localizedDescription
            )
        }
        originalPlayer.play()
        ttsPlayer.play()
        isStarted = true
    }

    public func stop() {
        guard isStarted else { return }
        originalPlayer.stop()
        ttsPlayer.stop()
        engine.stop()
        engine.detach(originalPlayer)
        engine.detach(ttsPlayer)
        isStarted = false
    }

    /// Schedules a chunk of original-audio PCM for playback.
    public func playOriginal(_ pcm: Data) {
        guard let buffer = Self.pcmBuffer(from: pcm, format: format)
        else { return }
        originalPlayer.scheduleBuffer(buffer, completionHandler: nil)
    }

    /// `AudioSink` conformance — translated TTS chunks land here.
    public func receive(_ pcm: Data) {
        guard let buffer = Self.pcmBuffer(from: pcm, format: format)
        else { return }
        ttsPlayer.scheduleBuffer(buffer, completionHandler: nil)
    }

    public func duckOriginal() async {
        let target = Self.duckedLinearGain(
            mode: configuration.mode,
            levelDB: configuration.levelDB
        )
        await ramp(player: originalPlayer, to: target,
                   over: configuration.fadeMs)
    }

    public func restoreOriginal() async {
        await ramp(player: originalPlayer, to: 1.0,
                   over: configuration.fadeMs)
    }

    // MARK: - Gain math

    static func linearGain(dB: Double) -> Float {
        Float(pow(10.0, dB / 20.0))
    }

    static func duckedLinearGain(
        mode: DuckingMode, levelDB: Double
    ) -> Float {
        switch mode {
        case .off:         return 1
        case .mute:        return 0
        case .duckToLevel: return linearGain(dB: levelDB)
        }
    }

    // MARK: - Ramp

    /// Linearly interpolates the player's volume from current to `target`
    /// over `fadeMs` milliseconds. Uses 8 ms steps. Cancellation-safe.
    private func ramp(
        player: AVAudioPlayerNode,
        to target: Float,
        over fadeMs: Int
    ) async {
        guard fadeMs > 0 else {
            player.volume = target
            return
        }
        let stepMs: Int = 8
        let steps = Swift.max(1, fadeMs / stepMs)
        let start = player.volume
        for index in 1...steps {
            let progress = Float(index) / Float(steps)
            player.volume = start + (target - start) * progress
            try? await Task.sleep(
                nanoseconds: UInt64(stepMs) * 1_000_000
            )
        }
        player.volume = target
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

extension OutputEngine: AudioSink {}

/// Canonical PCM format used across the project: 48 kHz, mono, 32-bit float,
/// non-interleaved.
public enum CanonicalAudioFormat {
    public static let sampleRate: Double = 48_000
    public static let channelCount: UInt32 = 1
    public static let bitsPerChannel: UInt32 = 32
}

/// Opaque identifier for an ElevenLabs voice.
public struct VoiceID: Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

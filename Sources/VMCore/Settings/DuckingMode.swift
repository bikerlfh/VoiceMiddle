/// How the original speaker's audio is mixed with the translated TTS playing
/// in the user's output device.
///
/// - `off`: original audio plays at full level alongside the translation.
/// - `duckToLevel`: original audio is attenuated by the configured dB level
///   while the translation plays.
/// - `mute`: original audio is silenced while the translation plays.
public enum DuckingMode: String, Hashable, CaseIterable, Sendable {
    case off
    case duckToLevel
    case mute
}

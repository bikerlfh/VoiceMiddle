/// How a translation pipeline paces itself relative to incoming audio.
///
/// - `turnBased`: wait for the speaker to finish a phrase (VAD-detected
///   silence) before translating, then play the translated audio.
/// - `streaming`: translate at clause boundaries while the speaker is still
///   talking, accepting some risk of mid-utterance correction in exchange
///   for lower perceived latency.
public enum PaceMode: String, Hashable, CaseIterable, Sendable {
    case turnBased
    case streaming
}

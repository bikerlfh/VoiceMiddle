/// Direction of a translation pipeline relative to the local user.
///
/// `inbound` carries audio from the remote party to the local user's output
/// device. `outbound` carries audio from the local user's microphone into
/// the virtual microphone consumed by the communication app.
public enum Direction: String, Hashable, CaseIterable, Sendable {
    case inbound
    case outbound
}

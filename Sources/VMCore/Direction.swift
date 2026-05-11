/// Direction of a translation pipeline relative to the local user.
///
/// `inbound` carries audio from the remote party into the user's headphones.
/// `outbound` carries audio from the user's microphone into the virtual
/// microphone consumed by the communication app.
public enum Direction: String, Sendable, CaseIterable, Hashable {
    case inbound
    case outbound
}

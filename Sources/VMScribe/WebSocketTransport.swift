import Foundation

/// Minimal abstraction over a WebSocket connection that ``ScribeV2StreamClient``
/// can use. Allows tests to inject a deterministic fake.
public protocol WebSocketTransport: Sendable {
    /// Establishes the connection. Throws on transport-level failure.
    func connect(url: URL, headers: [String: String]) async throws

    /// Sends a binary frame.
    func send(_ data: Data) async throws

    /// Sends a text frame.
    func sendText(_ text: String) async throws

    /// Returns the next incoming frame. `nil` indicates the peer closed the
    /// connection cleanly.
    func receive() async throws -> WebSocketFrame?

    /// Closes the connection.
    func close() async
}

public enum WebSocketFrame: Sendable, Equatable {
    case text(String)
    case binary(Data)
}

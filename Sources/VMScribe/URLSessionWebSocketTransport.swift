import Foundation

/// `URLSessionWebSocketTask`-backed implementation of ``WebSocketTransport``.
///
/// `@unchecked Sendable` is justified: the only mutable state is `task`, which
/// is assigned exactly once from `connect(url:headers:)` and cleared in
/// `close()`. Callers respect the protocol contract of one task per direction,
/// so there is no contention to guard.
public final class URLSessionWebSocketTransport: WebSocketTransport,
                                                 @unchecked Sendable {
    private let session: URLSession
    private var task: URLSessionWebSocketTask?

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func connect(url: URL, headers: [String: String]) async throws {
        var request = URLRequest(url: url)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
    }

    public func send(_ data: Data) async throws {
        try await task?.send(.data(data))
    }

    public func sendText(_ text: String) async throws {
        try await task?.send(.string(text))
    }

    public func receive() async throws -> WebSocketFrame? {
        guard let task else { return nil }
        let message = try await task.receive()
        switch message {
        case .data(let data): return .binary(data)
        case .string(let s):  return .text(s)
        @unknown default:     return nil
        }
    }

    public func close() async {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }
}

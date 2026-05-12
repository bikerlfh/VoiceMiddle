import Testing
import Foundation
@preconcurrency import AVFoundation
import VMCore
@testable import VMScribe

@Suite("ScribeV2StreamClient")
struct ScribeV2StreamClientTests {
    @Test("Decodes partials and finals in order from the transport")
    func roundTrip() async throws {
        let transport = FakeWebSocketTransport()
        let client = ScribeV2StreamClient(
            url: URL(string: "wss://test.invalid")!,
            apiKey: "test-key",
            sourceLanguage: try LanguageCode("en"),
            transport: transport
        )

        await client.connect()

        // Queue server frames the read loop will consume.
        await transport.queueIncoming([
            .text(#"{"message_type":"session_started","session_id":"x"}"#),
            .text(#"{"message_type":"partial_transcript","text":"hello"}"#),
            .text(#"{"message_type":"partial_transcript","text":"hello wor"}"#),
            .text(#"{"message_type":"committed_transcript","text":"hello world"}"#),
        ])

        let partialsStream = client.partials
        let finalsStream = client.finals

        let partialsTask = Task { () -> [String] in
            var observed: [String] = []
            for await partial in partialsStream {
                observed.append(partial)
                if observed.count == 2 { break }
            }
            return observed
        }
        let finalsTask = Task { () -> String? in
            for await final in finalsStream {
                return final
            }
            return nil
        }

        let observedPartials = await partialsTask.value
        let lastFinal = await finalsTask.value

        #expect(observedPartials == ["hello", "hello wor"])
        #expect(lastFinal == "hello world")

        // No start frame is sent on connect; the docs replace it with query
        // parameters on the URL.
        let sent = await transport.sentText
        #expect(sent.isEmpty)
        await client.close()
    }

    @Test("Server error frame surfaces as STTError.server")
    func serverError() async throws {
        let transport = FakeWebSocketTransport()
        let client = ScribeV2StreamClient(
            url: URL(string: "wss://test.invalid")!,
            apiKey: "k",
            sourceLanguage: try LanguageCode("en"),
            transport: transport
        )
        await client.connect()
        await transport.queueIncoming([
            .text(#"{"message_type":"auth_error","error":"invalid key"}"#)
        ])

        let errorsStream = client.errors
        let errorsTask = Task { () -> STTError? in
            for await error in errorsStream { return error }
            return nil
        }
        let observed = await errorsTask.value
        #expect(observed == .server(message: "invalid key"))
        await client.close()
    }
}

/// Test transport that yields pre-queued frames from `receive()` and records
/// every frame sent. Thread-safe; the actor under test calls into it from a
/// single task at a time.
actor FakeWebSocketTransport: WebSocketTransport {
    private var incoming: [WebSocketFrame] = []
    private var waiter: CheckedContinuation<WebSocketFrame?, Error>?
    private(set) var sentText: [String] = []
    private(set) var sentBinary: [Data] = []
    private var open = false

    func connect(url: URL, headers: [String: String]) async throws {
        open = true
    }

    func send(_ data: Data) async throws {
        sentBinary.append(data)
    }

    func sendText(_ text: String) async throws {
        sentText.append(text)
    }

    func receive() async throws -> WebSocketFrame? {
        if !incoming.isEmpty {
            return incoming.removeFirst()
        }
        if !open {
            return nil
        }
        return try await withCheckedThrowingContinuation { c in
            self.waiter = c
        }
    }

    func queueIncoming(_ frames: [WebSocketFrame]) {
        incoming.append(contentsOf: frames)
        if let w = waiter, !incoming.isEmpty {
            waiter = nil
            w.resume(returning: incoming.removeFirst())
        }
    }

    func close() async {
        open = false
        if let w = waiter {
            waiter = nil
            w.resume(returning: nil)
        }
    }
}

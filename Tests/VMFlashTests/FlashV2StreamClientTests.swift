import Testing
import Foundation
import VMCore
@testable import VMFlash

@Suite("FlashV2StreamClient")
struct FlashV2StreamClientTests {
    @Test("Round trip: queued chunks flow through the sink in order")
    func roundTrip() async throws {
        let transport = FakeFlashTransport()
        let client = FlashV2StreamClient(
            apiKey: "test",
            makeTransport: { transport }
        )

        let chunkA: [Float] = [0.1, 0.2, 0.3]
        let chunkB: [Float] = [-0.1, -0.2]
        let dataA = chunkA.withUnsafeBytes { Data($0) }
        let dataB = chunkB.withUnsafeBytes { Data($0) }

        await transport.queueIncoming([
            .text(#"{"audio":"\#(dataA.base64EncodedString())","isFinal":false}"#),
            .text(#"{"audio":"\#(dataB.base64EncodedString())","isFinal":false}"#),
            .text(#"{"isFinal":true}"#),
        ])

        let collected = Collected()
        try await client.synthesize(
            "hello world",
            voice: VoiceID("v1"),
            sink: { data in Task { await collected.append(data) } }
        )

        // Allow the sink Tasks to drain.
        try await Task.sleep(for: .milliseconds(20))

        let chunks = await collected.values
        #expect(chunks.count == 2)
        #expect(chunks[0] == dataA)
        #expect(chunks[1] == dataB)

        let sent = await transport.sentText
        #expect(sent.count == 3)
        #expect(sent[0].contains("xi_api_key"))
        #expect(sent[1].contains("hello world"))
        #expect(sent[2].contains("\"text\":\"\""))
    }

    @Test("Empty text throws TTSError.empty")
    func empty() async {
        let transport = FakeFlashTransport()
        let client = FlashV2StreamClient(
            apiKey: "test", makeTransport: { transport }
        )
        await #expect(throws: TTSError.empty) {
            try await client.synthesize(
                "   ",
                voice: VoiceID("v1"),
                sink: { _ in }
            )
        }
    }

    @Test("Endpoint URL includes voice id, model id, and output format")
    func endpoint() async throws {
        let transport = FakeFlashTransport()
        let client = FlashV2StreamClient(
            apiKey: "k", makeTransport: { transport }
        )
        await transport.queueIncoming([.text(#"{"isFinal":true}"#)])
        try await client.synthesize(
            "hi",
            voice: VoiceID("alpha"),
            sink: { _ in }
        )
        let connected = await transport.connectURL
        let url = try #require(connected)
        #expect(url.path.contains("/alpha/stream-input"))
        let query = url.query ?? ""
        #expect(query.contains("model_id=eleven_flash_v2_5"))
        #expect(query.contains("output_format=pcm_48000"))
        #expect(query.contains("optimize_streaming_latency=3"))
    }
}

actor Collected {
    private(set) var values: [Data] = []
    func append(_ d: Data) { values.append(d) }
}

actor FakeFlashTransport: WebSocketTransport {
    private var incoming: [WebSocketFrame] = []
    private var waiter: CheckedContinuation<WebSocketFrame?, Error>?
    private(set) var sentText: [String] = []
    private(set) var connectURL: URL?
    private var open = false

    func connect(url: URL, headers: [String: String]) async throws {
        connectURL = url
        open = true
    }
    func send(_ data: Data) async throws {}
    func sendText(_ text: String) async throws {
        sentText.append(text)
    }
    func receive() async throws -> WebSocketFrame? {
        if !incoming.isEmpty {
            return incoming.removeFirst()
        }
        if !open { return nil }
        return try await withCheckedThrowingContinuation { c in
            waiter = c
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

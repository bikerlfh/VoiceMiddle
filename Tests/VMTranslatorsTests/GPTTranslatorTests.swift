import Testing
import Foundation
import VMCore
@testable import VMTranslators

extension VMTranslatorsSuite {
@Suite("GPTTranslator")
struct GPTTranslatorTests {
    @Test("identifier and supportsContext")
    func identifierAndContext() {
        let translator = GPTTranslator(apiKey: "k")
        #expect(translator.identifier == .gpt4oMini)
        #expect(translator.supportsContext == true)
    }

    @Test("Round trip returns the response text trimmed")
    func roundTrip() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        let translator = GPTTranslator(
            apiKey: "k", session: makeMockSession()
        )
        MockURLProtocol.handler = { _ in
            (
                HTTPURLResponse(
                    url: URL(
                        string: "https://api.openai.com/v1/chat/completions")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data(#"""
                {
                  "id": "chatcmpl_1",
                  "object": "chat.completion",
                  "choices": [
                    {
                      "index": 0,
                      "message": {
                        "role": "assistant",
                        "content": "  Hola mundo\n"
                      },
                      "finish_reason": "stop"
                    }
                  ]
                }
                """#.utf8)
            )
        }

        let translated = try await translator.translate(
            "Hello world",
            from: try LanguageCode("en"),
            to: try LanguageCode("es"),
            context: nil
        )
        #expect(translated == "Hola mundo")
    }

    @Test("Request body contains required OpenAI fields")
    func requestShape() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        let translator = GPTTranslator(
            apiKey: "secret", session: makeMockSession()
        )
        MockURLProtocol.handler = { _ in
            (HTTPURLResponse(
                url: URL(
                    string: "https://api.openai.com/v1/chat/completions")!,
                statusCode: 200, httpVersion: nil, headerFields: nil
            )!, Data(#"""
                {"choices":[{"message":{"role":"assistant","content":"ok"}}]}
                """#.utf8))
        }
        _ = try await translator.translate(
            "Hi",
            from: try LanguageCode("en"),
            to: try LanguageCode("es"),
            context: nil
        )

        let captured = try #require(MockURLProtocol.capturedRequests.first)
        #expect(
            captured.value(forHTTPHeaderField: "Authorization")
                == "Bearer secret"
        )
        #expect(
            captured.value(forHTTPHeaderField: "Content-Type")
                == "application/json"
        )
        let body = try #require(
            captured.httpBody ?? captured.httpBodyStream.flatMap(readAll)
        )
        let json = try #require(
            try JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        #expect((json["model"] as? String) == "gpt-4o-mini")
        #expect((json["temperature"] as? Double) == 0)
        let messages = try #require(json["messages"] as? [[String: Any]])
        #expect(!messages.isEmpty)
        let firstMessage = try #require(messages.first)
        #expect(firstMessage["role"] as? String == "system")
        let systemContent = try #require(firstMessage["content"] as? String)
        #expect(systemContent.contains("interpreter"))
    }

    @Test("Conversation context becomes alternating messages")
    func contextEmbedding() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        let translator = GPTTranslator(
            apiKey: "k", session: makeMockSession()
        )
        MockURLProtocol.handler = { _ in
            (HTTPURLResponse(
                url: URL(
                    string: "https://api.openai.com/v1/chat/completions")!,
                statusCode: 200, httpVersion: nil, headerFields: nil
            )!, Data(#"""
                {"choices":[{"message":{"role":"assistant","content":"ok"}}]}
                """#.utf8))
        }

        let now = Date()
        let context = ConversationContext(
            recentTurns: [
                .init(direction: .inbound,
                      original: "Hey, can you hear me?",
                      translated: "¿Me oyes?",
                      timestamp: now.addingTimeInterval(-10)),
                .init(direction: .outbound,
                      original: "Sí, perfectamente.",
                      translated: "Yes, perfectly.",
                      timestamp: now.addingTimeInterval(-5)),
            ],
            sessionTopicHint: "engineering interview"
        )
        _ = try await translator.translate(
            "What did you mean by that?",
            from: try LanguageCode("en"),
            to: try LanguageCode("es"),
            context: context
        )

        let captured = try #require(MockURLProtocol.capturedRequests.first)
        let body = try #require(captured.httpBody)
        let json = try #require(
            try JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        let messages = try #require(json["messages"] as? [[String: Any]])

        // Expected layout:
        //   [0] system: interpreter prompt + topic hint
        //   [1] user: turn 1 original
        //   [2] assistant: turn 1 translated
        //   [3] user: turn 2 original
        //   [4] assistant: turn 2 translated
        //   [5] user: new utterance + translate directive
        #expect(messages.count == 6)

        let system = try #require(messages.first)
        #expect(system["role"] as? String == "system")
        let systemContent = try #require(system["content"] as? String)
        #expect(systemContent.contains("engineering interview"))

        let m1 = messages[1]
        #expect(m1["role"] as? String == "user")
        #expect((m1["content"] as? String) == "Hey, can you hear me?")
        let m2 = messages[2]
        #expect(m2["role"] as? String == "assistant")
        #expect((m2["content"] as? String) == "¿Me oyes?")
        let m3 = messages[3]
        #expect(m3["role"] as? String == "user")
        #expect((m3["content"] as? String) == "Sí, perfectamente.")
        let m4 = messages[4]
        #expect(m4["role"] as? String == "assistant")
        #expect((m4["content"] as? String) == "Yes, perfectly.")

        let last = try #require(messages.last)
        #expect(last["role"] as? String == "user")
        let lastContent = try #require(last["content"] as? String)
        #expect(lastContent.contains("What did you mean by that?"))
        #expect(lastContent.contains("en"))
        #expect(lastContent.contains("es"))
    }

}
}

private func readAll(_ stream: InputStream) -> Data {
    stream.open(); defer { stream.close() }
    var buffer = [UInt8](repeating: 0, count: 4096)
    var data = Data()
    while stream.hasBytesAvailable {
        let n = stream.read(&buffer, maxLength: buffer.count)
        if n <= 0 { break }
        data.append(buffer, count: n)
    }
    return data
}

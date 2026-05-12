import Testing
import Foundation
import VMCore
@testable import VMTranslators

@Suite("ClaudeTranslator", .serialized)
struct ClaudeTranslatorTests {
    @Test("identifier and supportsContext")
    func identifierAndContext() {
        let translator = ClaudeTranslator(apiKey: "k")
        #expect(translator.identifier == .claudeHaiku45)
        #expect(translator.supportsContext == true)
    }

    @Test("Round trip returns the response text trimmed")
    func roundTrip() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        let translator = ClaudeTranslator(
            apiKey: "k", session: makeMockSession()
        )
        MockURLProtocol.handler = { _ in
            (
                HTTPURLResponse(
                    url: URL(string: "https://api.anthropic.com/v1/messages")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data(#"""
                {
                  "id": "msg_1",
                  "type": "message",
                  "role": "assistant",
                  "content": [{"type": "text", "text": "  Hola mundo\n"}],
                  "model": "claude-haiku-4-5-20251001",
                  "stop_reason": "end_turn"
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

    @Test("Request body contains required Anthropic fields")
    func requestShape() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        let translator = ClaudeTranslator(
            apiKey: "secret", session: makeMockSession()
        )
        MockURLProtocol.handler = { _ in
            (HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/v1/messages")!,
                statusCode: 200, httpVersion: nil, headerFields: nil
            )!, Data(#"{"content":[{"type":"text","text":"ok"}]}"#.utf8))
        }
        _ = try await translator.translate(
            "Hi",
            from: try LanguageCode("en"),
            to: try LanguageCode("es"),
            context: nil
        )

        let captured = try #require(MockURLProtocol.capturedRequests.first)
        #expect(captured.value(forHTTPHeaderField: "x-api-key") == "secret")
        #expect(
            captured.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01"
        )
        #expect(
            captured.value(forHTTPHeaderField: "content-type") == "application/json"
        )
        let body = try #require(
            captured.httpBody ?? captured.httpBodyStream.flatMap(readAll)
        )
        let json = try #require(
            try JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        #expect((json["model"] as? String) == "claude-haiku-4-5-20251001")
        #expect((json["max_tokens"] as? Int) == 1024)
        #expect((json["temperature"] as? Double) == 0)
        let system = try #require(json["system"] as? [[String: Any]])
        let firstSystem = try #require(system.first)
        let cacheControl = try #require(
            firstSystem["cache_control"] as? [String: Any]
        )
        #expect(cacheControl["type"] as? String == "ephemeral")
        let messages = try #require(json["messages"] as? [[String: Any]])
        #expect(!messages.isEmpty)
    }

    @Test("Conversation context becomes structured turns in the messages array")
    func contextEmbedding() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        let translator = ClaudeTranslator(
            apiKey: "k", session: makeMockSession()
        )
        MockURLProtocol.handler = { _ in
            (HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/v1/messages")!,
                statusCode: 200, httpVersion: nil, headerFields: nil
            )!, Data(#"{"content":[{"type":"text","text":"ok"}]}"#.utf8))
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

        // We expect a single user message describing context + the new line.
        let firstMessage = try #require(messages.first)
        #expect(firstMessage["role"] as? String == "user")
        let content = try #require(firstMessage["content"] as? String)
        #expect(content.contains("Hey, can you hear me?"))
        #expect(content.contains("¿Me oyes?"))
        #expect(content.contains("engineering interview"))
        #expect(content.contains("What did you mean by that?"))
    }

    @Test("Empty source throws emptySource")
    func emptySource() async throws {
        let translator = ClaudeTranslator(
            apiKey: "k", session: makeMockSession()
        )
        await #expect(throws: TranslationError.emptySource) {
            _ = try await translator.translate(
                "",
                from: try LanguageCode("en"),
                to: try LanguageCode("es"),
                context: nil
            )
        }
    }

    @Test("HTTP 5xx surfaces as upstream error with statusCode")
    func upstream5xx() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        let translator = ClaudeTranslator(
            apiKey: "k", session: makeMockSession()
        )
        MockURLProtocol.handler = { _ in
            (HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/v1/messages")!,
                statusCode: 503, httpVersion: nil, headerFields: nil
            )!, Data("service unavailable".utf8))
        }
        await #expect(throws: TranslationError.self) {
            _ = try await translator.translate(
                "Hi",
                from: try LanguageCode("en"),
                to: try LanguageCode("es"),
                context: nil
            )
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

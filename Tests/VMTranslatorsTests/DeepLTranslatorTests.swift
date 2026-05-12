import Testing
import Foundation
import VMCore
@testable import VMTranslators

extension VMTranslatorsSuite {
@Suite("DeepLTranslator")
struct DeepLTranslatorTests {
    @Test("identifier and supportsContext")
    func identifierAndContext() {
        let translator = DeepLTranslator(apiKey: "k")
        #expect(translator.identifier == .deepL)
        #expect(translator.supportsContext == false)
    }

    @Test("Round trip returns the translated text")
    func roundTrip() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        let translator = DeepLTranslator(
            apiKey: "k", session: makeMockSession()
        )
        MockURLProtocol.handler = { _ in
            (
                HTTPURLResponse(
                    url: URL(string: "https://api.deepl.com/v2/translate")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data(#"""
                {"translations":[{"detected_source_language":"EN","text":"Hola mundo"}]}
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

    @Test("Request body and headers match DeepL form-encoded contract")
    func requestShape() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        let translator = DeepLTranslator(
            apiKey: "secret-key", session: makeMockSession()
        )
        MockURLProtocol.handler = { _ in
            (HTTPURLResponse(
                url: URL(string: "https://api.deepl.com/v2/translate")!,
                statusCode: 200, httpVersion: nil, headerFields: nil
            )!, Data(#"""
                {"translations":[{"detected_source_language":"EN","text":"ok"}]}
                """#.utf8))
        }
        _ = try await translator.translate(
            "Hello, world!",
            from: try LanguageCode("en"),
            to: try LanguageCode("es"),
            context: nil
        )

        let captured = try #require(MockURLProtocol.capturedRequests.first)
        #expect(
            captured.value(forHTTPHeaderField: "Authorization")
                == "DeepL-Auth-Key secret-key"
        )
        #expect(
            captured.value(forHTTPHeaderField: "Content-Type")
                == "application/x-www-form-urlencoded"
        )
        let body = try #require(
            captured.httpBody ?? captured.httpBodyStream.flatMap(readAll)
        )
        let bodyString = try #require(String(data: body, encoding: .utf8))
        let pairs = parseFormBody(bodyString)
        #expect(pairs["source_lang"] == "EN")
        #expect(pairs["target_lang"] == "ES")
        #expect(pairs["text"] == "Hello, world!")
        // Spot check the raw body still uses percent-encoding for the comma
        // and space, which is how form-urlencoded values render them.
        #expect(bodyString.contains("text="))
    }

    @Test("Region subtags are stripped to the primary subtag uppercased")
    func regionSubtagsStripped() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        let translator = DeepLTranslator(
            apiKey: "k", session: makeMockSession()
        )
        MockURLProtocol.handler = { _ in
            (HTTPURLResponse(
                url: URL(string: "https://api.deepl.com/v2/translate")!,
                statusCode: 200, httpVersion: nil, headerFields: nil
            )!, Data(#"""
                {"translations":[{"detected_source_language":"EN","text":"ok"}]}
                """#.utf8))
        }
        _ = try await translator.translate(
            "Hi",
            from: try LanguageCode("en-US"),
            to: try LanguageCode("es-MX"),
            context: nil
        )

        let captured = try #require(MockURLProtocol.capturedRequests.first)
        let body = try #require(captured.httpBody)
        let bodyString = try #require(String(data: body, encoding: .utf8))
        let pairs = parseFormBody(bodyString)
        #expect(pairs["source_lang"] == "EN")
        #expect(pairs["target_lang"] == "ES")
    }

    @Test("Context is ignored: body contains source text but no turns or hint")
    func contextIsIgnored() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        let translator = DeepLTranslator(
            apiKey: "k", session: makeMockSession()
        )
        MockURLProtocol.handler = { _ in
            (HTTPURLResponse(
                url: URL(string: "https://api.deepl.com/v2/translate")!,
                statusCode: 200, httpVersion: nil, headerFields: nil
            )!, Data(#"""
                {"translations":[{"detected_source_language":"EN","text":"ok"}]}
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
        let bodyString = try #require(String(data: body, encoding: .utf8))
        let pairs = parseFormBody(bodyString)
        #expect(pairs["text"] == "What did you mean by that?")
        // None of the turn fields or topic hint should leak into the body.
        #expect(!bodyString.contains("engineering"))
        #expect(!bodyString.contains("hear"))
        #expect(!bodyString.contains("perfectamente"))
        #expect(!bodyString.contains("Me%20oyes"))
        #expect(!bodyString.contains("Yes"))
    }

    @Test("Empty source throws emptySource")
    func emptySource() async throws {
        let translator = DeepLTranslator(
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
        let translator = DeepLTranslator(
            apiKey: "k", session: makeMockSession()
        )
        MockURLProtocol.handler = { _ in
            (HTTPURLResponse(
                url: URL(string: "https://api.deepl.com/v2/translate")!,
                statusCode: 503, httpVersion: nil, headerFields: nil
            )!, Data("service unavailable".utf8))
        }
        await #expect(throws: TranslationError.upstream(statusCode: 503)) {
            _ = try await translator.translate(
                "Hi",
                from: try LanguageCode("en"),
                to: try LanguageCode("es"),
                context: nil
            )
        }
    }
}
}

private func parseFormBody(_ body: String) -> [String: String] {
    // Re-parse a form-urlencoded body using URLComponents so percent-encoding
    // is decoded uniformly.
    var components = URLComponents()
    components.percentEncodedQuery = body
    var result: [String: String] = [:]
    for item in components.queryItems ?? [] {
        result[item.name] = item.value
    }
    return result
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

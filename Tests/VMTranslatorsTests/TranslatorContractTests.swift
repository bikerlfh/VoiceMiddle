import Testing
import Foundation
import VMCore
@testable import VMTranslators

/// Parameterized tests that exercise behaviour every ``Translator`` shares —
/// namely, empty-source validation, surfacing of upstream 5xx errors, and a
/// minimal happy-path round trip. Provider-specific request shapes and
/// context-embedding behaviour stay in the per-translator suites because
/// their assertions differ.
extension VMTranslatorsSuite {
    @Suite("TranslatorContract", .serialized)
    struct TranslatorContractTests {
        struct Subject: Sendable, CustomTestStringConvertible {
            let id: String
            let make: @Sendable (URLSession) -> any Translator
            let canned200: @Sendable () -> Data
            let endpoint: URL

            var testDescription: String { id }
        }

        static let subjects: [Subject] = [
            Subject(
                id: "claude",
                make: { ClaudeTranslator(apiKey: "k", session: $0) },
                canned200: {
                    Data(#"{"content":[{"type":"text","text":"ok"}]}"#.utf8)
                },
                endpoint:
                    URL(string: "https://api.anthropic.com/v1/messages")!
            ),
            Subject(
                id: "gpt",
                make: { GPTTranslator(apiKey: "k", session: $0) },
                canned200: {
                    Data(#"{"choices":[{"message":{"content":"ok"}}]}"#.utf8)
                },
                endpoint:
                    URL(string: "https://api.openai.com/v1/chat/completions")!
            ),
            Subject(
                id: "deepl",
                make: { DeepLTranslator(apiKey: "k", session: $0) },
                canned200: {
                    Data(#"{"translations":[{"text":"ok"}]}"#.utf8)
                },
                endpoint:
                    URL(string: "https://api.deepl.com/v2/translate")!
            ),
        ]

        @Test(
            "Empty source throws TranslationError.emptySource",
            arguments: subjects
        )
        func emptySource(subject: Subject) async throws {
            let session = makeMockSession()
            let translator = subject.make(session)
            await #expect(throws: TranslationError.emptySource) {
                _ = try await translator.translate(
                    "",
                    from: try LanguageCode("en"),
                    to: try LanguageCode("es"),
                    context: nil
                )
            }
        }

        @Test(
            "HTTP 5xx surfaces as upstream error",
            arguments: subjects
        )
        func upstream5xx(subject: Subject) async throws {
            MockURLProtocol.reset()
            defer { MockURLProtocol.reset() }
            MockURLProtocol.handler = { _ in
                (
                    HTTPURLResponse(
                        url: subject.endpoint,
                        statusCode: 503,
                        httpVersion: nil,
                        headerFields: nil
                    )!,
                    Data()
                )
            }
            let translator = subject.make(makeMockSession())
            await #expect(
                throws: TranslationError.upstream(statusCode: 503)
            ) {
                _ = try await translator.translate(
                    "Hello",
                    from: try LanguageCode("en"),
                    to: try LanguageCode("es"),
                    context: nil
                )
            }
        }

        @Test(
            "Successful round trip returns the trimmed payload",
            arguments: subjects
        )
        func roundTrip(subject: Subject) async throws {
            MockURLProtocol.reset()
            defer { MockURLProtocol.reset() }
            MockURLProtocol.handler = { _ in
                (
                    HTTPURLResponse(
                        url: subject.endpoint,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!,
                    subject.canned200()
                )
            }
            let translator = subject.make(makeMockSession())
            let result = try await translator.translate(
                "Hello",
                from: try LanguageCode("en"),
                to: try LanguageCode("es"),
                context: nil
            )
            #expect(result == "ok")
        }
    }
}

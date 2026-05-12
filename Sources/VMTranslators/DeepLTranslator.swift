import Foundation
import VMCore

/// DeepL REST translator.
///
/// DeepL provides the fastest of our supported backends but does not take
/// conversation context, so ``supportsContext`` is `false`. The endpoint is
/// configurable to switch between the Pro and Free-tier base URLs:
///
/// - Pro: `https://api.deepl.com/v2/translate` (default)
/// - Free: `https://api-free.deepl.com/v2/translate`
///
/// `DeepLTranslator` is an actor so its internal `URLSession` is accessed
/// from a single isolation domain, which simplifies Sendable reasoning under
/// Swift 6.
public actor DeepLTranslator: Translator {
    public nonisolated let identifier: TranslatorID = .deepL
    public nonisolated let supportsContext: Bool = false

    private let apiKey: String
    private let session: URLSession
    private let endpoint: URL

    public init(
        apiKey: String,
        session: URLSession = .shared,
        endpoint: URL = URL(
            string: "https://api.deepl.com/v2/translate")!
    ) {
        self.apiKey = apiKey
        self.session = session
        self.endpoint = endpoint
    }

    public func translate(
        _ text: String,
        from source: LanguageCode,
        to target: LanguageCode,
        context: ConversationContext?    // intentionally ignored
    ) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationError.emptySource }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue(
            "DeepL-Auth-Key \(apiKey)",
            forHTTPHeaderField: "Authorization"
        )
        request.httpBody = Self.encodeBody(
            text: trimmed, source: source, target: target
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw TranslationError.transport(
                message: error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.transport(message: "Non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw TranslationError.upstream(statusCode: http.statusCode)
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data),
            let dict = json as? [String: Any],
            let translations = dict["translations"] as? [[String: Any]],
            let first = translations.first,
            let translated = first["text"] as? String
        else {
            throw TranslationError.decode(
                message: "Could not extract translations[0].text"
            )
        }

        let result = translated.trimmingCharacters(
            in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw TranslationError.emptyResponse }
        return result
    }

    // MARK: - Request body

    /// Builds an `application/x-www-form-urlencoded` body for DeepL. We use
    /// `URLComponents.percentEncodedQuery` because it applies the correct
    /// percent-encoding for query values out of the box, and the same parser
    /// can recover the pairs on the test side.
    private static func encodeBody(
        text: String, source: LanguageCode, target: LanguageCode
    ) -> Data {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "text", value: text),
            URLQueryItem(name: "source_lang",
                         value: source.primarySubtag.uppercased()),
            URLQueryItem(name: "target_lang",
                         value: target.primarySubtag.uppercased()),
        ]
        return Data((components.percentEncodedQuery ?? "").utf8)
    }
}

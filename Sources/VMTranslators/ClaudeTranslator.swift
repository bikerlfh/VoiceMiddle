import Foundation
import VMCore

/// Anthropic-Messages-API-backed translator.
///
/// Uses the REST endpoint at `https://api.anthropic.com/v1/messages` over
/// `URLSession`. The static system prompt is marked `cache_control: ephemeral`
/// so Anthropic prompt-caches it across the session.
///
/// `ClaudeTranslator` is an actor so its internal `URLSession` is accessed
/// from a single isolation domain, which simplifies Sendable reasoning under
/// Swift 6.
public actor ClaudeTranslator: Translator {
    public nonisolated let identifier: TranslatorID = .claudeHaiku45
    public nonisolated let supportsContext: Bool = true

    private let apiKey: String
    private let session: URLSession
    private let model: String
    private let endpoint: URL

    public init(
        apiKey: String,
        session: URLSession = .shared,
        model: String = "claude-haiku-4-5-20251001",
        endpoint: URL = URL(
            string: "https://api.anthropic.com/v1/messages")!
    ) {
        self.apiKey = apiKey
        self.session = session
        self.model = model
        self.endpoint = endpoint
    }

    public func translate(
        _ text: String,
        from source: LanguageCode,
        to target: LanguageCode,
        context: ConversationContext?
    ) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationError.emptySource }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json",
                         forHTTPHeaderField: "content-type")
        request.setValue("2023-06-01",
                         forHTTPHeaderField: "anthropic-version")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

        let body = Self.buildRequestBody(
            model: model,
            text: trimmed,
            source: source,
            target: target,
            context: context
        )
        request.httpBody = try JSONSerialization.data(
            withJSONObject: body, options: [])

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
            let content = dict["content"] as? [[String: Any]],
            let first = content.first,
            let translated = first["text"] as? String
        else {
            throw TranslationError.decode(
                message: "Could not extract content[0].text"
            )
        }

        let result = translated.trimmingCharacters(
            in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw TranslationError.emptyResponse }
        return result
    }

    // MARK: - Request body

    private static func buildRequestBody(
        model: String,
        text: String,
        source: LanguageCode,
        target: LanguageCode,
        context: ConversationContext?
    ) -> [String: Any] {
        let systemBlock: [String: Any] = [
            "type": "text",
            "text": Self.systemPrompt,
            "cache_control": ["type": "ephemeral"],
        ]
        let userMessage = Self.renderUserMessage(
            text: text,
            source: source,
            target: target,
            context: context
        )
        return [
            "model": model,
            "max_tokens": 1024,
            "temperature": 0,
            "system": [systemBlock],
            "messages": [
                ["role": "user", "content": userMessage]
            ],
        ]
    }

    private static let systemPrompt: String = """
        You are a real-time interpreter.
        Translate the user's utterance literally and preserve register.
        Do not add commentary, do not apologize, do not summarize.
        Output only the translated utterance, nothing else.
        """

    private static func renderUserMessage(
        text: String,
        source: LanguageCode,
        target: LanguageCode,
        context: ConversationContext?
    ) -> String {
        var sections: [String] = []
        if let context, !context.recentTurns.isEmpty
           || context.sessionTopicHint != nil {
            if let hint = context.sessionTopicHint {
                sections.append("Session topic: \(hint)")
            }
            if !context.recentTurns.isEmpty {
                var lines = ["Recent turns (oldest first):"]
                for turn in context.recentTurns {
                    let who = turn.direction == .inbound ? "REMOTE" : "LOCAL"
                    lines.append("- \(who): \(turn.original)")
                    lines.append("  \u{2192} \(turn.translated)")
                }
                sections.append(lines.joined(separator: "\n"))
            }
        }
        sections.append(
            "Translate from \(source) to \(target):\n\(text)"
        )
        return sections.joined(separator: "\n\n")
    }
}

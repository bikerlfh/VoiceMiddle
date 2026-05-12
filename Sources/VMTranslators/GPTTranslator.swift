import Foundation
import VMCore

/// OpenAI Chat Completions-backed translator.
///
/// Uses the REST endpoint at `https://api.openai.com/v1/chat/completions`
/// over `URLSession`. Conversation context is rendered as a `messages[]`
/// few-shot history: a `system` message with the interpreter prompt, then
/// alternating `user`/`assistant` messages carrying recent original/translated
/// pairs, then the new `user` message with the utterance to translate.
///
/// `GPTTranslator` is an actor so its internal `URLSession` is accessed
/// from a single isolation domain, which simplifies Sendable reasoning under
/// Swift 6.
public actor GPTTranslator: Translator {
    public nonisolated let identifier: TranslatorID = .gpt4oMini
    public nonisolated let supportsContext: Bool = true

    private let apiKey: String
    private let session: URLSession
    private let model: String
    private let endpoint: URL

    public init(
        apiKey: String,
        session: URLSession = .shared,
        model: String = "gpt-4o-mini",
        endpoint: URL = URL(
            string: "https://api.openai.com/v1/chat/completions")!
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
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let messages = Self.buildMessages(
            text: trimmed,
            source: source,
            target: target,
            context: context
        )
        let body: [String: Any] = [
            "model": model,
            "temperature": 0,
            "messages": messages,
        ]
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
            let choices = dict["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw TranslationError.decode(
                message: "Could not extract choices[0].message.content"
            )
        }

        let result = content.trimmingCharacters(
            in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw TranslationError.emptyResponse }
        return result
    }

    // MARK: - Message rendering

    private static func buildMessages(
        text: String,
        source: LanguageCode,
        target: LanguageCode,
        context: ConversationContext?
    ) -> [[String: String]] {
        var systemContent = Self.systemPrompt
        if let hint = context?.sessionTopicHint {
            systemContent += "\n\nSession topic: \(hint)"
        }
        var messages: [[String: String]] = [
            ["role": "system", "content": systemContent]
        ]
        if let context {
            for turn in context.recentTurns {
                // Render each recent turn as a user/assistant pair: the
                // original utterance is what the user asked the interpreter
                // to translate, and the translated text is the assistant's
                // prior response. This gives the model a faithful few-shot
                // history of the conversation.
                messages.append(
                    ["role": "user", "content": turn.original])
                messages.append(
                    ["role": "assistant", "content": turn.translated])
            }
        }
        messages.append([
            "role": "user",
            "content": "Translate from \(source) to \(target):\n\(text)",
        ])
        return messages
    }

    private static let systemPrompt: String = """
        You are a real-time interpreter.
        Translate the user's utterance literally and preserve register.
        Do not add commentary, do not apologize, do not summarize.
        Output only the translated utterance, nothing else.
        """
}

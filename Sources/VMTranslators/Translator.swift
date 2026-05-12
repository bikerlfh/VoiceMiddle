import Foundation
import VMCore

/// Identifies a specific translator implementation. Used by Settings and by
/// orchestrators to select the right backend at runtime.
public enum TranslatorID: String, Hashable, CaseIterable, Sendable {
    case claudeHaiku45
    case gpt4oMini
    case deepL
}

/// Errors surfaced by any ``Translator`` implementation.
public enum TranslationError: Error, Hashable, Sendable {
    /// The caller passed an empty or whitespace-only source string.
    case emptySource
    /// The upstream returned a non-2xx HTTP status code.
    case upstream(statusCode: Int)
    /// The upstream payload could not be decoded.
    case decode(message: String)
    /// The upstream responded with a 2xx payload that contained no text.
    case emptyResponse
    /// A transport-level error before getting a response.
    case transport(message: String)
}

/// A pluggable text translator.
///
/// Implementations must be safe to call concurrently because the two pipelines
/// (inbound and outbound) share a single translator instance.
///
/// Translators that consult conversation context declare ``supportsContext``
/// as `true`; orchestrators pass `nil` to translators that do not.
public protocol Translator: Sendable {
    var identifier: TranslatorID { get }
    var supportsContext: Bool { get }

    /// Translates ``text`` from ``source`` to ``target``.
    ///
    /// - Parameters:
    ///   - text: The source utterance. Empty / whitespace-only input throws
    ///     ``TranslationError/emptySource``.
    ///   - source: BCP-47 language code of the input, e.g. `"en"`.
    ///   - target: BCP-47 language code of the output, e.g. `"es"`.
    ///   - context: Recent turns from both directions, or `nil` when the
    ///     translator does not support context.
    func translate(
        _ text: String,
        from source: LanguageCode,
        to target: LanguageCode,
        context: ConversationContext?
    ) async throws -> String
}

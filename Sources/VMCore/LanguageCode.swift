import Foundation

/// A BCP-47 language code such as `en` or `en-US`.
///
/// Validation here is intentionally light: subtags must be ASCII letters,
/// separated by single hyphens, with no leading or trailing hyphen and no
/// embedded whitespace. Upstream APIs (Scribe, translators) perform the
/// authoritative validation.
public struct LanguageCode: Hashable, CustomStringConvertible, Sendable {
    public enum Error: Swift.Error, Equatable { case invalid(String) }

    public let rawValue: String
    public let primarySubtag: String

    public init(_ rawValue: String) throws {
        let invalid = Error.invalid(rawValue)
        let trimmed = rawValue.trimmingCharacters(in: .whitespaces)
        guard trimmed == rawValue, !trimmed.isEmpty else { throw invalid }
        guard !trimmed.contains("--") else { throw invalid }
        guard let first = trimmed.first, let last = trimmed.last,
              first.isLetter, last.isLetter,
              trimmed.allSatisfy({ $0.isASCII && ($0.isLetter || $0 == "-") })
        else { throw invalid }
        self.rawValue = trimmed
        self.primarySubtag = trimmed.split(separator: "-").first
            .map(String.init)?.lowercased() ?? trimmed.lowercased()
    }

    public var description: String { rawValue }
}

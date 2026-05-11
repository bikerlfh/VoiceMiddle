import Foundation

/// A BCP-47 language code such as `en` or `en-US`.
///
/// Validation here is intentionally light: we accept any non-empty string of
/// ASCII letters and hyphens. Upstream APIs (Scribe, translators) perform the
/// authoritative validation.
public struct LanguageCode: Hashable, Sendable, CustomStringConvertible {
    public enum Error: Swift.Error, Equatable { case invalid(String) }

    public let rawValue: String
    public let primarySubtag: String

    public init(_ rawValue: String) throws {
        let trimmed = rawValue.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              trimmed.allSatisfy({ $0.isASCII && ($0.isLetter || $0 == "-") })
        else { throw Error.invalid(rawValue) }
        self.rawValue = trimmed
        self.primarySubtag = trimmed.split(separator: "-").first.map {
            $0.lowercased()
        } ?? trimmed.lowercased()
    }

    public var description: String { rawValue }
}

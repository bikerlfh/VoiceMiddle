import Testing
import VMCore

@Suite("LanguageCode")
struct LanguageCodeTests {
    @Test("Primary subtag is lowercased for the single-subtag form")
    func singleSubtagLowercase() throws {
        let code = try LanguageCode("EN")
        #expect(code.rawValue == "EN")
        #expect(code.primarySubtag == "en")
    }

    @Test("Two-subtag form round-trips and extracts the primary subtag")
    func twoSubtagRoundTrip() throws {
        let code = try LanguageCode("en-US")
        #expect(code.rawValue == "en-US")
        #expect(code.primarySubtag == "en")
    }

    @Test("Multi-subtag form extracts only the primary subtag")
    func multiSubtag() throws {
        let code = try LanguageCode("zh-Hant-HK")
        #expect(code.primarySubtag == "zh")
    }

    @Test("Equal raw values produce equal LanguageCodes")
    func equalityAndHashing() throws {
        let a = try LanguageCode("en-US")
        let b = try LanguageCode("en-US")
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test(
        "Malformed inputs are rejected",
        arguments: [
            "",            // empty
            "   ",         // whitespace only
            " en-US",      // leading whitespace
            "en-US ",      // trailing whitespace
            "en US",       // embedded whitespace
            "-en",         // leading hyphen
            "en-",         // trailing hyphen
            "en--US",      // double hyphen
            "-",           // only hyphen
            "--",          // only hyphens
            "en1",         // contains digit (strict ASCII-letters rule)
            "日本語",       // non-ASCII
            "en\u{00A0}US" // non-breaking space (non-ASCII whitespace)
        ]
    )
    func rejectsMalformed(input: String) {
        #expect(throws: LanguageCode.Error.self) {
            _ = try LanguageCode(input)
        }
    }
}

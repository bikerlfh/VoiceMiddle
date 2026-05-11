import Testing
@testable import VMCore

@Suite("LanguageCode")
struct LanguageCodeTests {
    @Test("BCP-47 strings round-trip")
    func roundTrip() throws {
        let code = try LanguageCode("en-US")
        #expect(code.rawValue == "en-US")
        #expect(code.primarySubtag == "en")
    }

    @Test("Invalid strings throw")
    func invalidThrows() {
        #expect(throws: LanguageCode.Error.self) {
            _ = try LanguageCode("")
        }
    }

    @Test("Primary subtag is lowercased")
    func primarySubtagLowercased() throws {
        let code = try LanguageCode("EN")
        #expect(code.primarySubtag == "en")
    }
}

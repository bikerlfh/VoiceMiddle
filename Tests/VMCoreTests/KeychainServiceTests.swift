import Testing
import Foundation
import VMCore

@Suite("KeychainService")
struct KeychainServiceTests {
    /// Each test uses a unique service string so concurrent test runs cannot
    /// observe one another's items. Tests delete their items on the way out
    /// to keep the user keychain clean.
    private func makeService() -> KeychainService {
        KeychainService(service: "com.voicemiddle.tests.\(UUID().uuidString)")
    }

    @Test("Store then fetch returns the stored value")
    func storeAndFetch() throws {
        let keychain = makeService()
        defer { try? keychain.deleteAll() }
        try keychain.set("sk-test-abc", forAccount: "elevenlabs")
        #expect(try keychain.string(forAccount: "elevenlabs") == "sk-test-abc")
    }

    @Test("Fetching a missing account returns nil")
    func missingReturnsNil() throws {
        let keychain = makeService()
        defer { try? keychain.deleteAll() }
        #expect(try keychain.string(forAccount: "nope") == nil)
    }

    @Test("Setting twice updates the value in place")
    func updatesInPlace() throws {
        let keychain = makeService()
        defer { try? keychain.deleteAll() }
        try keychain.set("v1", forAccount: "anthropic")
        try keychain.set("v2", forAccount: "anthropic")
        #expect(try keychain.string(forAccount: "anthropic") == "v2")
    }

    @Test("Delete removes a specific account")
    func deleteSpecific() throws {
        let keychain = makeService()
        defer { try? keychain.deleteAll() }
        try keychain.set("x", forAccount: "openai")
        try keychain.set("y", forAccount: "deepl")
        try keychain.delete(account: "openai")
        #expect(try keychain.string(forAccount: "openai") == nil)
        #expect(try keychain.string(forAccount: "deepl") == "y")
    }

    @Test("Distinct services don't see each other's values")
    func serviceIsolation() throws {
        let a = makeService()
        let b = makeService()
        defer { try? a.deleteAll(); try? b.deleteAll() }
        try a.set("alpha", forAccount: "shared")
        try b.set("beta", forAccount: "shared")
        #expect(try a.string(forAccount: "shared") == "alpha")
        #expect(try b.string(forAccount: "shared") == "beta")
    }

    @Test("deleteAll removes every account for the service")
    func deleteAll() throws {
        let keychain = makeService()
        try keychain.set("a", forAccount: "one")
        try keychain.set("b", forAccount: "two")
        try keychain.deleteAll()
        #expect(try keychain.string(forAccount: "one") == nil)
        #expect(try keychain.string(forAccount: "two") == nil)
    }
}

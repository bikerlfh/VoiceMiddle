import Testing
import Foundation
import VMCore

@Suite("SettingsStore")
struct SettingsStoreTests {
    private func ephemeralDefaults() -> UserDefaults {
        UserDefaults(suiteName: UUID().uuidString)!
    }

    @Test("Defaults match the spec")
    func defaults() {
        let store = SettingsStore(defaults: ephemeralDefaults())
        #expect(store.paceMode(for: .inbound) == .turnBased)
        #expect(store.paceMode(for: .outbound) == .turnBased)
        #expect(store.readOnlyInbound == false)
        #expect(store.duckingMode == .duckToLevel)
        #expect(abs(store.duckingLevelDB - (-20)) < 0.01)
    }

    @Test("Per-direction pace mode round-trips through a fresh store")
    func paceRoundTrip() {
        let defaults = ephemeralDefaults()
        let a = SettingsStore(defaults: defaults)
        a.setPaceMode(.streaming, for: .inbound)
        let b = SettingsStore(defaults: defaults)
        #expect(b.paceMode(for: .inbound) == .streaming)
        #expect(b.paceMode(for: .outbound) == .turnBased)
    }

    @Test("readOnlyInbound persists")
    func readOnlyPersist() {
        let defaults = ephemeralDefaults()
        let a = SettingsStore(defaults: defaults)
        a.readOnlyInbound = true
        let b = SettingsStore(defaults: defaults)
        #expect(b.readOnlyInbound == true)
    }

    @Test("Ducking mode and level persist")
    func duckingPersist() {
        let defaults = ephemeralDefaults()
        let a = SettingsStore(defaults: defaults)
        a.duckingMode = .mute
        a.duckingLevelDB = -12.5
        let b = SettingsStore(defaults: defaults)
        #expect(b.duckingMode == .mute)
        #expect(abs(b.duckingLevelDB - (-12.5)) < 0.01)
    }

    @Test("Unknown raw values fall back to defaults")
    func unknownRawFallsBack() {
        let defaults = ephemeralDefaults()
        defaults.set("nonsense", forKey: "vm.settings.paceInbound")
        defaults.set("nonsense", forKey: "vm.settings.duckingMode")
        let store = SettingsStore(defaults: defaults)
        #expect(store.paceMode(for: .inbound) == .turnBased)
        #expect(store.duckingMode == .duckToLevel)
    }
}

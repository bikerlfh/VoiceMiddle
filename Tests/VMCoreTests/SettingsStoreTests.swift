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

    @Test("hasCompletedOnboarding round-trips")
    func onboardingFlag() {
        let defaults = ephemeralDefaults()
        let a = SettingsStore(defaults: defaults)
        #expect(a.hasCompletedOnboarding == false)
        a.hasCompletedOnboarding = true
        let b = SettingsStore(defaults: defaults)
        #expect(b.hasCompletedOnboarding == true)
    }

    @Test("selectedTargetBundleID round-trips and clears on nil")
    func targetBundleID() {
        let defaults = ephemeralDefaults()
        let a = SettingsStore(defaults: defaults)
        #expect(a.selectedTargetBundleID == nil)
        a.selectedTargetBundleID = "com.example.app"
        let b = SettingsStore(defaults: defaults)
        #expect(b.selectedTargetBundleID == "com.example.app")
        b.selectedTargetBundleID = nil
        let c = SettingsStore(defaults: defaults)
        #expect(c.selectedTargetBundleID == nil)
    }

    @Test("launchAtLogin defaults to false and round-trips")
    func launchAtLoginRoundTrip() {
        let defaults = ephemeralDefaults()
        let a = SettingsStore(defaults: defaults)
        #expect(a.launchAtLogin == false)
        a.launchAtLogin = true
        let b = SettingsStore(defaults: defaults)
        #expect(b.launchAtLogin == true)
    }

    @Test("hudOpacity defaults to 0.85 and round-trips")
    func hudOpacityRoundTrip() {
        let defaults = ephemeralDefaults()
        let a = SettingsStore(defaults: defaults)
        #expect(abs(a.hudOpacity - 0.85) < 0.001)
        a.hudOpacity = 0.65
        let b = SettingsStore(defaults: defaults)
        #expect(abs(b.hudOpacity - 0.65) < 0.001)
    }

    @Test("Global hotkey persistence")
    func hotkeyRoundTrip() {
        let defaults = ephemeralDefaults()
        let a = SettingsStore(defaults: defaults)
        #expect(a.globalHotkeyKeyCode == nil)
        #expect(a.globalHotkeyModifierFlags == nil)
        a.globalHotkeyKeyCode = 9            // V
        a.globalHotkeyModifierFlags = 1_572_864 // option + command (mock)
        let b = SettingsStore(defaults: defaults)
        #expect(b.globalHotkeyKeyCode == 9)
        #expect(b.globalHotkeyModifierFlags == 1_572_864)
        b.globalHotkeyKeyCode = nil
        b.globalHotkeyModifierFlags = nil
        let c = SettingsStore(defaults: defaults)
        #expect(c.globalHotkeyKeyCode == nil)
        #expect(c.globalHotkeyModifierFlags == nil)
    }
}

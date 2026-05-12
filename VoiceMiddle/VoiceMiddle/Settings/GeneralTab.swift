import ServiceManagement
import SwiftUI
import VMCore

/// "General" tab of the Settings scene. Covers app-level chrome:
///
/// - Launch at login (registered with `SMAppService.mainApp`).
/// - HUD opacity slider (0.5 ... 1.0).
/// - Global hotkey display + Clear. Actual rebinding of the hotkey is
///   deferred to a follow-up task; the Clear button revokes any custom
///   binding so the built-in default (⌥⌘V, applied when Accessibility
///   is granted) takes over.
struct GeneralTab: View {
    let settings: SettingsStore

    @State private var launchAtLogin: Bool
    @State private var hudOpacity: Double
    @State private var hotkeyDisplay: String
    @State private var hasCustomHotkey: Bool

    init(settings: SettingsStore) {
        self.settings = settings
        _launchAtLogin = State(initialValue: settings.launchAtLogin)
        _hudOpacity = State(initialValue: settings.hudOpacity)
        _hotkeyDisplay = State(
            initialValue: Self.format(
                keyCode: settings.globalHotkeyKeyCode,
                modifiers: settings.globalHotkeyModifierFlags
            )
        )
        _hasCustomHotkey = State(
            initialValue: settings.globalHotkeyKeyCode != nil
        )
    }

    var body: some View {
        Form {
            Section("Startup") {
                Toggle(
                    "Launch VoiceMiddle at login",
                    isOn: $launchAtLogin
                )
                .onChange(of: launchAtLogin) { _, new in
                    settings.launchAtLogin = new
                    Self.applyLaunchAtLogin(new)
                }
            }

            Section("Transcript HUD") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Opacity")
                    Slider(value: $hudOpacity, in: 0.5...1.0)
                        .onChange(of: hudOpacity) { _, new in
                            settings.hudOpacity = new
                        }
                    Text(String(format: "%.0f%%", hudOpacity * 100))
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            Section("Global hotkey") {
                HStack {
                    Text("Toggle session:")
                    Text(hotkeyDisplay)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") {
                        settings.globalHotkeyKeyCode = nil
                        settings.globalHotkeyModifierFlags = nil
                        hotkeyDisplay = Self.format(
                            keyCode: nil, modifiers: nil
                        )
                        hasCustomHotkey = false
                    }
                    .disabled(!hasCustomHotkey)
                }
                Text(
                    "Customizing the global hotkey requires Accessibility "
                    + "permission. Rebinding lands in a follow-up task; "
                    + "for now the default \u{2325}\u{2318}V is used if "
                    + "Accessibility is granted."
                )
                .foregroundStyle(.secondary)
                .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding(16)
    }

    // MARK: - Helpers

    private static func applyLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status == .notRegistered {
                    try service.register()
                }
            } else {
                if service.status == .enabled {
                    try service.unregister()
                }
            }
        } catch {
            // Best-effort: surfacing the error to the user lands in a
            // follow-up task once we have a unified error UI.
        }
    }

    private static func format(
        keyCode: UInt16?, modifiers: UInt?
    ) -> String {
        guard let keyCode else {
            return "(default \u{2325}\u{2318}V if granted)"
        }
        return "key \(keyCode), modifiers \(modifiers ?? 0)"
    }
}

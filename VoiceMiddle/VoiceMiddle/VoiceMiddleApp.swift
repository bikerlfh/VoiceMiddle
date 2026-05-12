import AppKit
import SwiftUI

@main
struct VoiceMiddleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(appDelegate: appDelegate)
        } label: {
            MenuBarLabel(driver: appDelegate.sessionDriver)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsTabsView(
                hudViewModel: appDelegate.hudViewModel,
                installer: appDelegate.systemExtensionInstaller,
                settings: appDelegate.settings,
                sessionDriver: appDelegate.sessionDriver
            )
        }
    }
}

/// SF-Symbol-backed menu bar icon that reflects ``SessionDriver`` state.
private struct MenuBarLabel: View {
    @ObservedObject var driver: SessionDriver

    var body: some View {
        Image(systemName: symbolName)
    }

    private var symbolName: String {
        switch driver.state {
        case .idle:    return "mic.slash"
        case .running: return "waveform"
        case .error:   return "exclamationmark.triangle"
        }
    }
}

/// Dropdown menu rendered when the user clicks the menu bar icon.
private struct MenuBarContent: View {
    let appDelegate: AppDelegate
    @ObservedObject private var driver: SessionDriver

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        self.driver = appDelegate.sessionDriver
    }

    var body: some View {
        Button(driver.state == .running ? "Stop session" : "Start session") {
            toggleSession()
        }
        .disabled(!isRunning && !driver.canStart())
        .keyboardShortcut("s", modifiers: [.command, .option])

        Divider()

        Button("Show transcript HUD") {
            appDelegate.hudWindowController.toggle()
        }
        .keyboardShortcut("h")

        Button("Diagnostics") {
            appDelegate.diagnosticsWindowController.toggle()
        }
        .keyboardShortcut("d", modifiers: [.command, .option])

        Divider()

        // SwiftUI-native Settings opener. macOS 14+ rejects the legacy
        // showSettingsWindow: selector with a runtime warning that also
        // suppresses the window from appearing.
        SettingsLink {
            Text("Preferences…")
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit VoiceMiddle") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var isRunning: Bool {
        driver.state == .running
    }

    private func toggleSession() {
        Task { @MainActor in
            if driver.state == .running {
                await driver.stop()
            } else {
                await driver.start()
            }
        }
    }
}

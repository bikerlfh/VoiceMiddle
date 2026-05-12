import SwiftUI

@main
struct VoiceMiddleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
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

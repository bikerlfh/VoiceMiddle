import SwiftUI

@main
struct VoiceMiddleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            DriverInstallView(installer: appDelegate.systemExtensionInstaller)
        }
    }
}

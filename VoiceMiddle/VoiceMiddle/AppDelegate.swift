import AppKit
import VMPipeline

/// Hosts the menu bar item and any other AppKit-only singletons.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let sessionController = SessionController()
    let systemExtensionInstaller = SystemExtensionInstaller(
        driverBundleID: "com.luismo.VoiceMiddleDriver"
    )
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        menuBarController = MenuBarController(controller: sessionController)
    }
}

import AppKit
import VMPipeline

/// Hosts the menu bar item and any other AppKit-only singletons.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let sessionController = SessionController()
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        menuBarController = MenuBarController(controller: sessionController)
    }
}

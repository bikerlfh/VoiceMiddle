import AppKit

/// Hosts the menu bar item and any other AppKit-only singletons. Real menu
/// bar wiring lands in Task 1.7.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

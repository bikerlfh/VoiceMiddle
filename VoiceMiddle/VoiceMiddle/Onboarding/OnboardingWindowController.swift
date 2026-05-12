import AppKit
import SwiftUI

/// Owns the `NSWindow` that hosts the first-launch onboarding wizard.
///
/// The wizard is presented modeless: showing it brings it forward and
/// activates the app, but it does not block the run loop. The menu bar
/// item remains responsive while the wizard is open. Calling ``hide()``
/// closes the window without releasing the controller — the same
/// controller could re-show the wizard later, e.g. from a Preferences
/// "Run setup again" button.
@MainActor
final class OnboardingWindowController {
    let viewModel: OnboardingViewModel
    private var window: NSWindow?

    init(viewModel: OnboardingViewModel) {
        self.viewModel = viewModel
    }

    func show() {
        if window == nil {
            window = makeWindow()
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        window?.close()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to VoiceMiddle"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(
            rootView: OnboardingView(viewModel: viewModel)
        )
        return window
    }
}

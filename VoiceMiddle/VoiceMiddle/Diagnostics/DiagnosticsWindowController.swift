import AppKit
import SwiftUI

/// Owns the borderless `NSWindow` that hosts ``DiagnosticsView``. Built
/// lazily so the metrics polling task only starts when the user opens the
/// window for the first time.
@MainActor
final class DiagnosticsWindowController {
    let viewModel: DiagnosticsViewModel
    private var window: NSWindow?

    init(viewModel: DiagnosticsViewModel) {
        self.viewModel = viewModel
    }

    func toggle() {
        if let window, window.isVisible {
            window.orderOut(nil)
            return
        }
        show()
    }

    func show() {
        if window == nil {
            window = makeWindow()
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSWindow {
        let panel = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 520, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Diagnostics"
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(
            rootView: DiagnosticsView(model: viewModel)
        )
        panel.minSize = NSSize(width: 480, height: 480)
        return panel
    }
}

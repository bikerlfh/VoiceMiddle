import AppKit
import SwiftUI

/// Owns the floating `NSPanel` that hosts ``HUDView``. The panel uses the
/// `nonactivatingPanel` style and the `.floating` level so showing the HUD
/// never steals focus from the underlying communication app.
@MainActor
final class HUDWindowController {
    let viewModel: HUDViewModel
    private var window: NSPanel?

    init(viewModel: HUDViewModel) {
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
        window?.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    private func makeWindow() -> NSPanel {
        let panel = NonActivatingPanel(
            contentRect: NSRect(x: 80, y: 80, width: 480, height: 360),
            styleMask: [
                .titled,
                .closable,
                .resizable,
                .nonactivatingPanel,
                .utilityWindow,
            ],
            backing: .buffered,
            defer: false
        )
        panel.title = "VoiceMiddle Transcript"
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let hostingView = NSHostingView(
            rootView: HUDView(model: viewModel)
                .background(VisualEffectView(material: .hudWindow))
        )
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: container.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        panel.contentView = container
        panel.minSize = NSSize(width: 360, height: 240)
        return panel
    }
}

/// Suppress key-window activation so the HUD never steals focus from the
/// underlying call window.
private final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Bridge to `NSVisualEffectView` so the SwiftUI background uses the HUD
/// material.
private struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

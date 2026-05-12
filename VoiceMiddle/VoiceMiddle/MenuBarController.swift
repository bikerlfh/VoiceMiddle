import AppKit
import VMPipeline

/// Renders the `NSStatusItem` for VoiceMiddle and binds it to a
/// ``SessionController`` so its icon and menu reflect the current session
/// state.
@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let controller: SessionController
    private let onToggleHUD: @MainActor () -> Void
    private var observerTask: Task<Void, Never>?

    init(
        controller: SessionController,
        onToggleHUD: @escaping @MainActor () -> Void
    ) {
        self.controller = controller
        self.onToggleHUD = onToggleHUD
        self.statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        configureButton(for: .idle)
        configureMenu()
        startObserving()
    }

    deinit {
        observerTask?.cancel()
    }

    private func configureButton(for state: SessionController.State) {
        guard let button = statusItem.button else { return }
        let symbolName: String
        switch state {
        case .idle:
            symbolName = "mic.slash"
        case .starting, .stopping:
            symbolName = "mic.badge.plus"
        case .active:
            symbolName = "waveform"
        }
        button.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "VoiceMiddle status: \(state.rawValue)"
        )
        button.image?.isTemplate = true
        button.toolTip = "VoiceMiddle (\(state.rawValue))"
    }

    private func configureMenu() {
        let menu = NSMenu()

        let toggleItem = NSMenuItem(
            title: "Toggle session",
            action: #selector(toggleSession),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        let hudItem = NSMenuItem(
            title: "Show transcript HUD",
            action: #selector(toggleHUD),
            keyEquivalent: "h"
        )
        hudItem.target = self
        menu.addItem(hudItem)

        menu.addItem(.separator())

        let preferencesItem = NSMenuItem(
            title: "Preferences…",
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit VoiceMiddle",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func startObserving() {
        let controller = self.controller
        observerTask = Task { @MainActor [weak self] in
            let states = await controller.states
            for await state in states {
                self?.configureButton(for: state)
            }
        }
    }

    @objc private func toggleSession() {
        Task { [controller] in
            let current = await controller.state
            switch current {
            case .idle, .stopping:
                await controller.start()
            case .starting, .active:
                await controller.stop()
            }
        }
    }

    @objc private func toggleHUD() {
        onToggleHUD()
    }

    @objc private func openPreferences() {
        // Preferences scene lands in Phase 4; for now this opens the default
        // SwiftUI Settings scene wired in VoiceMiddleApp.
        NSApp.sendAction(
            Selector(("showSettingsWindow:")),
            to: nil,
            from: nil
        )
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

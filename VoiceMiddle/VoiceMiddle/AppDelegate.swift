import AppKit
import VMCore
import VMPipeline

/// Hosts the menu bar item and any other AppKit-only singletons.
///
/// Owns the long-lived collaborators that need to outlive any single SwiftUI
/// view — most importantly the shared ``SessionDriver`` and
/// ``PipelineMetrics``. The Diagnostics window observes the same instances,
/// so opening it after a Settings window has been closed still sees current
/// state.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let sessionController = SessionController()
    let systemExtensionInstaller = SystemExtensionInstaller(
        driverBundleID: "com.luismo.VoiceMiddleDriver"
    )
    let hudViewModel = HUDViewModel()
    let settings = SettingsStore()
    let metrics = PipelineMetrics()
    lazy var sessionDriver: SessionDriver = SessionDriver(
        settings: settings,
        hudViewModel: hudViewModel,
        metrics: metrics
    )
    private(set) lazy var hudWindowController = HUDWindowController(
        viewModel: hudViewModel
    )
    private(set) lazy var diagnosticsWindowController:
        DiagnosticsWindowController = DiagnosticsWindowController(
            viewModel: DiagnosticsViewModel(
                metrics: metrics,
                driver: sessionDriver
            )
        )
    private var menuBarController: MenuBarController?
    private lazy var onboardingController: OnboardingWindowController = {
        let viewModel = OnboardingViewModel(
            installer: systemExtensionInstaller,
            settings: settings,
            onFinish: { [weak self] in
                self?.onboardingController.hide()
            }
        )
        return OnboardingWindowController(viewModel: viewModel)
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        menuBarController = MenuBarController(
            controller: sessionController,
            onToggleHUD: { [weak self] in
                self?.hudWindowController.toggle()
            },
            onToggleDiagnostics: { [weak self] in
                self?.diagnosticsWindowController.toggle()
            }
        )
        if !settings.hasCompletedOnboarding {
            onboardingController.show()
        }
    }
}

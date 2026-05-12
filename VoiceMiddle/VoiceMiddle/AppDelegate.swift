import AppKit
import MetricKit
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
    let crashReportStore = CrashReportStore()
    private var crashReportSubscriber: CrashReportSubscriber?
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
                driver: sessionDriver,
                crashReportStore: crashReportStore
            )
        )
    private var menuBarController: MenuBarController?

    /// Number of crash reports waiting on disk. The Diagnostics window
    /// surfaces this via its bound store; this accessor lets other UI (a
    /// future menu-bar badge, for instance) read the same count without
    /// owning a reference to the store.
    var pendingCrashReportCount: Int {
        crashReportStore.reports.count
    }
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
        let subscriber = CrashReportSubscriber(store: crashReportStore)
        crashReportSubscriber = subscriber
        MXMetricManager.shared.add(subscriber)
        if !settings.hasCompletedOnboarding {
            onboardingController.show()
        }
    }
}

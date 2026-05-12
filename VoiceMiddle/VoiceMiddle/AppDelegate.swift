import AppKit
import VMCore
import VMPipeline

/// Hosts the menu bar item and any other AppKit-only singletons.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let sessionController = SessionController()
    let systemExtensionInstaller = SystemExtensionInstaller(
        driverBundleID: "com.luismo.VoiceMiddleDriver"
    )
    let hudViewModel = HUDViewModel()
    let settings = SettingsStore()
    private(set) lazy var hudWindowController = HUDWindowController(
        viewModel: hudViewModel
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
            }
        )
        if !settings.hasCompletedOnboarding {
            onboardingController.show()
        }
    }
}

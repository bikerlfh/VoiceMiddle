import AVFoundation
import Combine
import Foundation
import SwiftUI
import VMAudio
import VMCore

/// View-model driving the three-step first-launch onboarding wizard.
///
/// Owns the wizard's transient state (current step, environment-key
/// presence flags, microphone permission status, observed driver-installer
/// status). Performs side-effects on behalf of the views (requesting
/// microphone access, kicking off the driver installation, persisting the
/// final choices to ``SettingsStore``).
@MainActor
final class OnboardingViewModel: ObservableObject {
    enum Step: Hashable {
        case permissions, apiKeys, targetApp
    }

    // MARK: - Published state

    @Published var currentStep: Step = .permissions
    @Published var elevenLabsKeyPresent: Bool = false
    @Published var deepLKeyPresent: Bool = false
    @Published var anthropicKeyPresent: Bool = false
    @Published var openAIKeyPresent: Bool = false
    @Published var microphoneStatus: AVAuthorizationStatus = .notDetermined
    @Published var availableProcesses: [AudioProcess] = []
    @Published var selectedProcessBundleID: String?
    @Published var driverStatus: SystemExtensionInstaller.Status = .unknown
    @Published var driverError: String?

    // MARK: - Dependencies

    let installer: SystemExtensionInstaller
    private let settings: SettingsStore
    private let onFinish: () -> Void
    private var statusObservationTask: Task<Void, Never>?

    // MARK: - Init

    init(
        installer: SystemExtensionInstaller,
        settings: SettingsStore,
        onFinish: @escaping () -> Void
    ) {
        self.installer = installer
        self.settings = settings
        self.onFinish = onFinish
        refreshAll()
        observeInstaller()
    }

    deinit {
        statusObservationTask?.cancel()
    }

    // MARK: - Refresh

    /// Re-reads every environment-driven flag (API key presence,
    /// microphone authorization, audio-process list). Safe to call from
    /// any view's `onAppear` or from the "Re-check" buttons.
    func refreshAll() {
        let env = ProcessInfo.processInfo.environment
        elevenLabsKeyPresent = !(env["ELEVENLABS_API_KEY"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        deepLKeyPresent = !(env["DEEPL_API_KEY"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        anthropicKeyPresent = !(env["ANTHROPIC_API_KEY"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        openAIKeyPresent = !(env["OPENAI_API_KEY"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        refreshProcesses()
    }

    func refreshProcesses() {
        availableProcesses = AudioProcess.enumerate()
            .filter { $0.bundleID != nil }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name)
                    == .orderedAscending
            }
    }

    // MARK: - Microphone

    /// Requests microphone access. Updates ``microphoneStatus`` with the
    /// authoritative system-reported value afterwards (rather than
    /// inferring from the granted bool) so a previous denial that survived
    /// the request shows up correctly.
    func requestMicrophone() async {
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    }

    func openMicrophoneSystemSettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Driver

    /// Asks the installer to activate the VoiceMiddle driver System
    /// Extension. Surfacing errors back to the UI so the user can still
    /// proceed (the driver only matters for the outbound side).
    func installDriver() async {
        driverError = nil
        do {
            try await installer.install()
        } catch {
            driverError = error.localizedDescription
        }
    }

    private func observeInstaller() {
        let installer = self.installer
        statusObservationTask = Task { [weak self] in
            let stream = await installer.statuses
            for await status in stream {
                await MainActor.run { [weak self] in
                    self?.driverStatus = status
                }
            }
        }
    }

    // MARK: - Navigation

    func next() {
        switch currentStep {
        case .permissions: currentStep = .apiKeys
        case .apiKeys:     currentStep = .targetApp
        case .targetApp:   finish()
        }
    }

    func back() {
        switch currentStep {
        case .permissions: return
        case .apiKeys:     currentStep = .permissions
        case .targetApp:   currentStep = .apiKeys
        }
    }

    func finish() {
        settings.selectedTargetBundleID = selectedProcessBundleID
        settings.hasCompletedOnboarding = true
        onFinish()
    }

    func skipTargetApp() {
        selectedProcessBundleID = nil
        finish()
    }
}

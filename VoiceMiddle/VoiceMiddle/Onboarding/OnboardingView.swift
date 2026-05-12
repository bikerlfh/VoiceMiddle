import SwiftUI

/// Root SwiftUI scene for the first-launch onboarding wizard. Renders the
/// progress dots, the current step's content, and the Back / Next /
/// Finish / Skip navigation buttons.
struct OnboardingView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            stepBody
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: .topLeading)
            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 480)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Text("Welcome to VoiceMiddle")
                .font(.title3).bold()
            progressDots
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
    }

    private var progressDots: some View {
        HStack(spacing: 10) {
            dot(for: .permissions)
            dot(for: .apiKeys)
            dot(for: .targetApp)
        }
    }

    private func dot(for step: OnboardingViewModel.Step) -> some View {
        let active = viewModel.currentStep == step
        return Circle()
            .fill(active ? Color.accentColor : Color.secondary.opacity(0.3))
            .frame(width: 8, height: 8)
            .accessibilityLabel(Text(label(for: step)))
    }

    private func label(for step: OnboardingViewModel.Step) -> String {
        switch step {
        case .permissions: return "Permissions"
        case .apiKeys:     return "API keys"
        case .targetApp:   return "Target app"
        }
    }

    // MARK: - Step body

    @ViewBuilder
    private var stepBody: some View {
        switch viewModel.currentStep {
        case .permissions:
            PermissionsStep(viewModel: viewModel)
        case .apiKeys:
            APIKeysStep(viewModel: viewModel)
        case .targetApp:
            TargetAppStep(viewModel: viewModel)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Back") { viewModel.back() }
                .disabled(viewModel.currentStep == .permissions)
            Spacer()
            if viewModel.currentStep == .targetApp {
                Button("Skip") { viewModel.skipTargetApp() }
            }
            Button(nextButtonTitle) { viewModel.next() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var nextButtonTitle: String {
        switch viewModel.currentStep {
        case .permissions, .apiKeys: return "Next"
        case .targetApp:             return "Finish"
        }
    }
}

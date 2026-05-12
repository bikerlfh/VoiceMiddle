import AVFoundation
import SwiftUI

/// Step 1 of the onboarding wizard. Shows the three permissions
/// VoiceMiddle relies on (microphone, system audio capture, driver System
/// Extension) and lets the user act on each one inline.
struct PermissionsStep: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Permissions")
                .font(.title2).bold()
            Text(
                "VoiceMiddle needs a few permissions to capture and translate"
                + " audio. You can grant them now or later — system prompts"
                + " will also appear the first time you start a session."
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            microphoneRow
            Divider()
            captureRow
            Divider()
            driverRow
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Microphone

    private var microphoneRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                statusIcon(for: microphoneState)
                Text("Microphone access").bold()
                Spacer()
                microphoneButton
            }
            Text(microphoneSubtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var microphoneButton: some View {
        switch viewModel.microphoneStatus {
        case .notDetermined:
            Button("Request access") {
                Task { await viewModel.requestMicrophone() }
            }
        case .denied, .restricted:
            Button("Open System Settings") {
                viewModel.openMicrophoneSystemSettings()
            }
        case .authorized:
            EmptyView()
        @unknown default:
            EmptyView()
        }
    }

    private var microphoneState: PermissionState {
        switch viewModel.microphoneStatus {
        case .authorized:               return .granted
        case .denied, .restricted:      return .denied
        case .notDetermined:            return .pending
        @unknown default:               return .pending
        }
    }

    private var microphoneSubtitle: String {
        switch viewModel.microphoneStatus {
        case .authorized:
            return "Granted."
        case .denied:
            return "Denied. Enable VoiceMiddle in System Settings → Privacy"
                + " & Security → Microphone."
        case .restricted:
            return "Restricted by system policy."
        case .notDetermined:
            return "Not yet requested. macOS will show a confirmation dialog."
        @unknown default:
            return "Status unknown."
        }
    }

    // MARK: - System audio capture

    private var captureRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                statusIcon(for: .pending)
                Text("Audio capture (Core Audio Process Taps)").bold()
                Spacer()
            }
            Text(
                "Granted at first run when you start a translation session."
                + " macOS will ask for permission then."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Driver

    private var driverRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                statusIcon(for: driverState)
                Text("System Extension (VoiceMiddle Driver)").bold()
                Spacer()
                driverButton
            }
            Text(driverSubtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let error = viewModel.driverError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var driverButton: some View {
        switch viewModel.driverStatus {
        case .installed:
            EmptyView()
        case .installing:
            ProgressView().controlSize(.small)
        default:
            Button("Install driver…") {
                Task { await viewModel.installDriver() }
            }
        }
    }

    private var driverState: PermissionState {
        switch viewModel.driverStatus {
        case .installed:                return .granted
        case .failed:                   return .denied
        case .installing, .needsApproval:
                                        return .pending
        case .unknown, .notInstalled:   return .pending
        }
    }

    private var driverSubtitle: String {
        switch viewModel.driverStatus {
        case .installed:
            return "Installed."
        case .installing:
            return "Installing — macOS may prompt for confirmation."
        case .needsApproval:
            return "Approve in System Settings → Privacy & Security."
        case .failed(let message):
            return "Failed: \(message)"
        case .notInstalled, .unknown:
            return "Required for the outbound (microphone → app) side."
                + " Inbound translation works without it."
        }
    }

    // MARK: - Status icon

    private enum PermissionState {
        case granted, denied, pending
    }

    @ViewBuilder
    private func statusIcon(for state: PermissionState) -> some View {
        switch state {
        case .granted:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .denied:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .pending:
            Image(systemName: "circle.dotted")
                .foregroundStyle(.secondary)
        }
    }
}

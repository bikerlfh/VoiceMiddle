import SwiftUI

struct DriverInstallView: View {
    let installer: SystemExtensionInstaller

    @State private var status: SystemExtensionInstaller.Status = .unknown
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("VoiceMiddle Driver")
                .font(.title2)
                .bold()

            Text("VoiceMiddle ships a virtual microphone driver that lets " +
                 "communication apps receive your translated voice. The " +
                 "driver must be activated once per machine.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Status:")
                statusLabel
                    .font(.system(.body, design: .monospaced))
            }

            HStack {
                Button(action: install) {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Install driver…")
                    }
                }
                .disabled(isWorking)

                if case .failed(let message) = status {
                    Text(message)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 480, minHeight: 240)
        .task {
            for await next in await installer.statuses {
                status = next
            }
        }
    }

    @ViewBuilder private var statusLabel: some View {
        switch status {
        case .unknown:        Text("unknown")
        case .notInstalled:   Text("not installed")
        case .needsApproval:  Text("waiting for user approval in System Settings…")
        case .installing:     Text("installing…")
        case .installed:      Text("installed").foregroundStyle(.green)
        case .failed:         Text("failed").foregroundStyle(.red)
        }
    }

    private func install() {
        isWorking = true
        Task {
            do {
                try await installer.install()
            } catch {
                // status will be .failed via the delegate
            }
            isWorking = false
        }
    }
}

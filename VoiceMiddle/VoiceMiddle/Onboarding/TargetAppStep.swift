import SwiftUI
import VMAudio

/// Step 3 of the onboarding wizard. Lets the user pick a default audio
/// target — the app whose output VoiceMiddle will translate when the user
/// starts a session without picking one explicitly.
struct TargetAppStep: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Default target app")
                .font(.title2).bold()
            Text(
                "Pick the app you most often want to translate (a"
                + " communication app like Zoom, Teams, Discord, etc.)."
                + " You can change this later in Preferences."
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text(processCountSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Refresh") { viewModel.refreshProcesses() }
            }

            if viewModel.availableProcesses.isEmpty {
                emptyState
            } else {
                processList
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { viewModel.refreshProcesses() }
    }

    // MARK: - List

    private var processList: some View {
        List(selection: selectionBinding) {
            ForEach(viewModel.availableProcesses, id: \.id) { process in
                row(for: process)
                    .tag(process.bundleID)
            }
        }
        .listStyle(.bordered)
        .frame(minHeight: 200)
    }

    private func row(for process: AudioProcess) -> some View {
        HStack(spacing: 8) {
            Image(systemName: process.isProducingAudio
                ? "waveform.circle.fill"
                : "app.dashed")
            .foregroundStyle(process.isProducingAudio
                ? AnyShapeStyle(Color.accentColor)
                : AnyShapeStyle(HierarchicalShapeStyle.secondary))
            VStack(alignment: .leading, spacing: 1) {
                Text(process.name)
                if let bundle = process.bundleID {
                    Text(bundle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No audio processes were found.")
                .foregroundStyle(.secondary)
            Text(
                "Open the app you want to translate (e.g. Zoom) and"
                + " click Refresh. Or click Skip to choose later."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
    }

    private var processCountSummary: String {
        let count = viewModel.availableProcesses.count
        if count == 1 { return "1 audio process available" }
        return "\(count) audio processes available"
    }

    // MARK: - Binding

    /// `List(selection:)` requires a `Set` for multi-select or a single
    /// value for single-select. We use the bundle ID as the row tag so
    /// the selection survives a process-list refresh as long as the
    /// process is still around.
    private var selectionBinding: Binding<String?> {
        Binding(
            get: { viewModel.selectedProcessBundleID },
            set: { viewModel.selectedProcessBundleID = $0 }
        )
    }
}

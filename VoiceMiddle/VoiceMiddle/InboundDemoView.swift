import CoreAudio
import SwiftUI
import VMAudio
import VMCore
import VMPipeline

/// Settings-scene UI for the Task 2.13 end-to-end inbound demo. Pairs
/// with ``InboundDemoViewModel``.
struct InboundDemoView: View {
    let hudViewModel: HUDViewModel
    @StateObject private var model: InboundDemoViewModel

    init(hudViewModel: HUDViewModel) {
        self.hudViewModel = hudViewModel
        _model = StateObject(
            wrappedValue: InboundDemoViewModel(
                hudViewModel: hudViewModel
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            targetAppPicker
            languagePickers
            voiceField
            readOnlyToggle
            controlRow
            if let error = model.lastError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            transcriptPane
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 520)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("VoiceMiddle inbound demo (Task 2.13)")
                .font(.title2).bold()
            HStack(spacing: 24) {
                keyStatusLabel(
                    title: "ElevenLabs API key",
                    available: model.elevenLabsKeyAvailable
                )
                keyStatusLabel(
                    title: "DeepL API key",
                    available: model.deepLKeyAvailable
                )
            }
        }
    }

    private func keyStatusLabel(title: String, available: Bool) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.callout)
            Text(available ? "\u{2713}" : "\u{2717}")
                .foregroundStyle(available ? .green : .red)
                .font(.system(.callout, design: .monospaced))
                .bold()
        }
    }

    private var targetAppPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Target app").font(.callout).bold()
                Spacer()
                Button("Refresh", action: model.refreshProcesses)
                    .controlSize(.small)
            }
            Picker(
                selection: Binding(
                    get: { model.selectedProcess?.id },
                    set: { newID in
                        model.selectedProcess = model.availableProcesses
                            .first { $0.id == newID }
                    }
                ),
                label: EmptyView()
            ) {
                if model.availableProcesses.isEmpty {
                    Text("No audio processes found")
                        .tag(Optional<AudioObjectID>.none)
                } else {
                    ForEach(model.availableProcesses, id: \.id) { proc in
                        Text(processLabel(proc))
                            .tag(Optional(proc.id))
                    }
                }
            }
            .labelsHidden()
        }
    }

    private func processLabel(_ proc: AudioProcess) -> String {
        var label = proc.name
        if proc.isProducingAudio { label += "  \u{1F50A}" }
        return label
    }

    private var languagePickers: some View {
        HStack(spacing: 24) {
            languagePicker(
                title: "Source",
                selection: $model.sourceLanguage
            )
            languagePicker(
                title: "Target",
                selection: $model.targetLanguage
            )
        }
    }

    private func languagePicker(
        title: String, selection: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.callout).bold()
            Picker(selection: selection, label: EmptyView()) {
                ForEach(model.supportedLanguages, id: \.self) { code in
                    Text(code).tag(code)
                }
            }
            .labelsHidden()
        }
    }

    private var voiceField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ElevenLabs voice ID").font(.callout).bold()
            TextField("voice id", text: $model.voiceID)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var readOnlyToggle: some View {
        Toggle(
            "Read-only (skip TTS toward me)",
            isOn: $model.readOnlyInbound
        )
        .help(
            "When enabled, the inbound pipeline only shows the live "
            + "transcript without synthesizing voice in your headphones. "
            + "Takes effect at next Start."
        )
    }

    private var controlRow: some View {
        HStack {
            Button(buttonTitle, action: toggleRun)
                .keyboardShortcut(.defaultAction)
                .disabled(buttonDisabled)
            stateLabel
            Spacer()
        }
    }

    private var buttonTitle: String {
        switch model.runState {
        case .idle:     return "Start"
        case .starting: return "Starting\u{2026}"
        case .running:  return "Stop"
        case .stopping: return "Stopping\u{2026}"
        }
    }

    private var buttonDisabled: Bool {
        switch model.runState {
        case .idle:
            return !model.canStart
        case .starting, .stopping:
            return true
        case .running:
            return false
        }
    }

    @ViewBuilder private var stateLabel: some View {
        switch model.runState {
        case .idle:     Text("idle").foregroundStyle(.secondary)
        case .starting: Text("starting\u{2026}")
        case .running:  Text("running").foregroundStyle(.green)
        case .stopping: Text("stopping\u{2026}")
        }
    }

    private func toggleRun() {
        switch model.runState {
        case .idle:     model.start()
        case .running:  model.stop()
        default:        return
        }
    }

    private var transcriptPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Transcript").font(.callout).bold()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if model.transcript.isEmpty {
                        Text("No events yet.")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    } else {
                        ForEach(model.transcript) { item in
                            TranscriptRow(item: item)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            .frame(minHeight: 160)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
        }
    }
}

private struct TranscriptRow: View {
    let item: TranscriptDisplayEvent

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(Self.timeFormatter.string(from: item.timestamp))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder private var content: some View {
        switch item.event {
        case .partial(_, let original):
            Text(original)
                .font(.callout)
                .foregroundStyle(.secondary)
        case .final(_, let original, let translated):
            VStack(alignment: .leading, spacing: 2) {
                Text(original).font(.callout)
                Text(translated)
                    .font(.callout)
                    .foregroundStyle(.blue)
            }
        case .error(_, let message):
            Text("error: \(message)")
                .font(.callout)
                .foregroundStyle(.red)
        }
    }
}

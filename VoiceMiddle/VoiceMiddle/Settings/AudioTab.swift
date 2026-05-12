import SwiftUI
import VMAudio
import VMCore
import VMPipeline

/// Audio settings tab. Surfaces the target-app picker, per-direction VAD
/// sensitivity, ducking configuration, the session Start/Stop button, and
/// an inline transcript pane.
///
/// All state lives in ``SettingsStore`` (persistent) and ``SessionDriver``
/// (transient). Local `@State` here merely mirrors the persistent values so
/// SwiftUI bindings remain ergonomic.
struct AudioTab: View {
    let hudViewModel: HUDViewModel
    @ObservedObject var driver: SessionDriver

    @State private var inboundSensitivity: Float
    @State private var outboundSensitivity: Float
    @State private var duckingMode: DuckingMode
    @State private var duckingLevelDB: Double
    @State private var duckingFadeMs: Int
    @State private var selectedBundleID: String?

    private let settings: SettingsStore

    init(
        hudViewModel: HUDViewModel,
        settings: SettingsStore,
        driver: SessionDriver
    ) {
        self.hudViewModel = hudViewModel
        self.settings = settings
        self.driver = driver
        _inboundSensitivity = State(
            initialValue: settings.vadSensitivity(for: .inbound)
        )
        _outboundSensitivity = State(
            initialValue: settings.vadSensitivity(for: .outbound)
        )
        _duckingMode = State(initialValue: settings.duckingMode)
        _duckingLevelDB = State(initialValue: settings.duckingLevelDB)
        _duckingFadeMs = State(initialValue: settings.duckingFadeMs)
        _selectedBundleID = State(
            initialValue: settings.selectedTargetBundleID
        )
    }

    var body: some View {
        Form {
            targetAppSection
            vadSection
            duckingSection
            sessionSection
            transcriptSection
        }
        .formStyle(.grouped)
        .padding(16)
    }

    // MARK: - Sections

    private var targetAppSection: some View {
        Section("Target app") {
            HStack {
                Picker("App", selection: $selectedBundleID) {
                    Text("(none)").tag(String?.none)
                    ForEach(driver.availableProcesses, id: \.id) { process in
                        Text(process.name)
                            .tag(Optional(process.bundleID ?? ""))
                    }
                }
                Button("Refresh") {
                    driver.refreshProcesses()
                }
            }
            .onChange(of: selectedBundleID) { _, new in
                settings.selectedTargetBundleID = new
            }
        }
    }

    private var vadSection: some View {
        Section("Voice activity detection") {
            VStack(alignment: .leading) {
                Text("Inbound energy threshold")
                Slider(value: $inboundSensitivity,
                       in: 0.001...0.05)
                    .onChange(of: inboundSensitivity) { _, new in
                        settings.setVADSensitivity(new, for: .inbound)
                    }
            }
            VStack(alignment: .leading) {
                Text("Outbound energy threshold")
                Slider(value: $outboundSensitivity,
                       in: 0.001...0.05)
                    .onChange(of: outboundSensitivity) { _, new in
                        settings.setVADSensitivity(new, for: .outbound)
                    }
            }
        }
    }

    private var duckingSection: some View {
        Section("Ducking") {
            Picker("Mode", selection: $duckingMode) {
                Text("Off").tag(DuckingMode.off)
                Text("Duck to level").tag(DuckingMode.duckToLevel)
                Text("Mute").tag(DuckingMode.mute)
            }
            .onChange(of: duckingMode) { _, new in
                settings.duckingMode = new
            }
            VStack(alignment: .leading) {
                Text("Ducking level dB")
                Slider(value: $duckingLevelDB, in: -40...0)
                    .disabled(duckingMode != .duckToLevel)
                    .onChange(of: duckingLevelDB) { _, new in
                        settings.duckingLevelDB = new
                    }
            }
            VStack(alignment: .leading) {
                Text("Fade duration (ms)")
                Slider(
                    value: Binding(
                        get: { Double(duckingFadeMs) },
                        set: { duckingFadeMs = Int($0) }
                    ),
                    in: 0...200,
                    step: 10
                )
                .onChange(of: duckingFadeMs) { _, new in
                    settings.duckingFadeMs = new
                }
            }
        }
    }

    private var sessionSection: some View {
        Section("Session") {
            HStack {
                Button(driver.state == .running ? "Stop" : "Start") {
                    Task {
                        if driver.state == .running {
                            await driver.stop()
                        } else {
                            await driver.start()
                        }
                    }
                }
                .disabled(driver.state != .running && !driver.canStart())
                if case .error(let message) = driver.state {
                    Text(message)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
    }

    private var transcriptSection: some View {
        Section("Transcript (this session)") {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(
                        0..<driver.transcript.count, id: \.self
                    ) { index in
                        transcriptRow(driver.transcript[index])
                    }
                }
                .padding(8)
            }
            .frame(minHeight: 160)
        }
    }

    @ViewBuilder
    private func transcriptRow(_ event: TranscriptEvent) -> some View {
        switch event {
        case .partial(let direction, let original):
            HStack {
                Text(direction == .inbound ? "\u{1F5E3}" : "\u{1F399}")
                Text(original).foregroundStyle(.secondary)
            }
        case .final(let direction, let original, let translated):
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(direction == .inbound ? "\u{1F5E3}" : "\u{1F399}")
                    Text(original).foregroundStyle(.secondary)
                }
                Text("\u{2192} \(translated)")
            }
        case .error(_, let message):
            HStack {
                Text("\u{26A0}")
                Text(message).foregroundStyle(.red)
            }
        }
    }
}

import SwiftUI
import VMCore

/// "Translation" tab of the Settings scene. Covers translator engine
/// selection, per-engine model override, the per-direction pace mode
/// (turn-based vs. streaming), and the read-only inbound toggle.
///
/// Selections are persisted to ``SettingsStore``. The running pipeline
/// will start reading from these properties in Task 4.4.
struct TranslationTab: View {
    let settings: SettingsStore

    @State private var engine: String
    @State private var claudeModel: String
    @State private var openAIModel: String
    @State private var paceInbound: PaceMode
    @State private var paceOutbound: PaceMode
    @State private var readOnlyInbound: Bool

    init(settings: SettingsStore) {
        self.settings = settings
        _engine = State(initialValue: settings.translatorIdentifier)
        _claudeModel = State(initialValue: settings.claudeModel)
        _openAIModel = State(initialValue: settings.openAIModel)
        _paceInbound = State(
            initialValue: settings.paceMode(for: .inbound)
        )
        _paceOutbound = State(
            initialValue: settings.paceMode(for: .outbound)
        )
        _readOnlyInbound = State(initialValue: settings.readOnlyInbound)
    }

    var body: some View {
        Form {
            Section("Engine") {
                Picker("Translator", selection: $engine) {
                    Text("Claude (Anthropic)").tag("claudeHaiku45")
                    Text("GPT (OpenAI)").tag("gpt4oMini")
                    Text("DeepL").tag("deepL")
                }
                .onChange(of: engine) { _, new in
                    settings.translatorIdentifier = new
                }
                if engine == "claudeHaiku45" {
                    TextField("Claude model", text: $claudeModel)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: claudeModel) { _, new in
                            settings.claudeModel = new
                        }
                }
                if engine == "gpt4oMini" {
                    TextField("OpenAI model", text: $openAIModel)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: openAIModel) { _, new in
                            settings.openAIModel = new
                        }
                }
                Text("API keys are read from environment variables: "
                     + "ELEVENLABS_API_KEY, DEEPL_API_KEY, "
                     + "ANTHROPIC_API_KEY, OPENAI_API_KEY.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Pace mode") {
                Picker("Inbound (other → you)", selection: $paceInbound) {
                    Text("Turn-based").tag(PaceMode.turnBased)
                    Text("Streaming").tag(PaceMode.streaming)
                }
                .onChange(of: paceInbound) { _, new in
                    settings.setPaceMode(new, for: .inbound)
                }

                Picker("Outbound (you → other)",
                       selection: $paceOutbound) {
                    Text("Turn-based").tag(PaceMode.turnBased)
                    Text("Streaming").tag(PaceMode.streaming)
                }
                .onChange(of: paceOutbound) { _, new in
                    settings.setPaceMode(new, for: .outbound)
                }
            }

            Section("Read-only mode") {
                Toggle("Skip TTS toward me (transcript only)",
                       isOn: $readOnlyInbound)
                    .onChange(of: readOnlyInbound) { _, new in
                        settings.readOnlyInbound = new
                    }
            }
        }
        .formStyle(.grouped)
        .padding(16)
    }
}

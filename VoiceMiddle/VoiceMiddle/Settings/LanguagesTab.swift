import SwiftUI
import VMCore

/// "Languages" tab of the Settings scene. Lets the user pick the source
/// and target language for translation, swap them, and configure the
/// ElevenLabs voice ID used for outbound TTS.
///
/// Selections are persisted to ``SettingsStore`` so they survive a relaunch.
/// The running pipeline does not read from these properties yet — wiring
/// lands in Task 4.4 — but the settings are functional and discoverable
/// today.
struct LanguagesTab: View {
    let settings: SettingsStore

    @State private var source: String
    @State private var target: String
    @State private var voiceID: String

    private static let languageOptions = [
        ("en", "English"),
        ("es", "Spanish"),
        ("de", "German"),
        ("fr", "French"),
        ("pt", "Portuguese"),
        ("it", "Italian"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("zh", "Chinese"),
    ]

    init(settings: SettingsStore) {
        self.settings = settings
        _source = State(initialValue: settings.sourceLanguageCode)
        _target = State(initialValue: settings.targetLanguageCode)
        _voiceID = State(initialValue: settings.voiceID)
    }

    var body: some View {
        Form {
            Section("Language pair") {
                Picker("Source", selection: $source) {
                    ForEach(Self.languageOptions, id: \.0) { code, label in
                        Text("\(label) (\(code))").tag(code)
                    }
                }
                .onChange(of: source) { _, new in
                    settings.sourceLanguageCode = new
                }

                Picker("Target", selection: $target) {
                    ForEach(Self.languageOptions, id: \.0) { code, label in
                        Text("\(label) (\(code))").tag(code)
                    }
                }
                .onChange(of: target) { _, new in
                    settings.targetLanguageCode = new
                }

                Button {
                    let swapped = source
                    source = target
                    target = swapped
                } label: {
                    Label("Swap", systemImage: "arrow.left.arrow.right")
                }
                .help("Swap source and target language")
            }

            Section("Voice") {
                TextField("ElevenLabs voice ID", text: $voiceID)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: voiceID) { _, new in
                        settings.voiceID = new
                    }
                Text("Default 21m00Tcm4TlvDq8ikWAM is Rachel — a public "
                     + "ElevenLabs voice. Voice preview lands when the "
                     + "outbound pipeline is wired.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding(16)
    }
}

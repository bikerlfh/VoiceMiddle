import SwiftUI
import AppKit
import VMCore

/// "Privacy" tab of the Settings scene. Lets the user toggle transcript
/// persistence, open or clear the transcripts folder, and jump to the
/// relevant System Settings panes for Microphone, Audio Capture, and
/// System Extensions permissions.
///
/// The transcript toggle is persisted to ``SettingsStore``. Actual
/// transcript storage and retention wiring lands in Task 4.8; the folder
/// shortcut and clear button operate on the canonical directory today
/// so they are immediately useful for inspecting demo output.
struct PrivacyTab: View {
    let settings: SettingsStore

    @State private var saveTranscripts: Bool

    init(settings: SettingsStore) {
        self.settings = settings
        _saveTranscripts = State(initialValue: settings.saveTranscripts)
    }

    var body: some View {
        Form {
            Section("Transcripts") {
                Toggle("Save session transcripts to disk",
                       isOn: $saveTranscripts)
                    .onChange(of: saveTranscripts) { _, new in
                        settings.saveTranscripts = new
                    }
                HStack {
                    Button("Open transcripts folder") {
                        openTranscriptsFolder()
                    }
                    Button("Clear all transcripts", role: .destructive) {
                        clearTranscripts()
                    }
                }
                Text("Transcripts are stored at "
                     + "~/Library/Application Support/VoiceMiddle/Transcripts/. "
                     + "Storage and persistence wiring lands in Task 4.8.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("System permissions") {
                Button("Open Microphone permission") {
                    openSystemPreferences(
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
                    )
                }
                Button("Open Audio Capture permission") {
                    openSystemPreferences(
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture"
                    )
                }
                Button("Open System Extensions") {
                    openSystemPreferences(
                        "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
                    )
                }
            }
        }
        .formStyle(.grouped)
        .padding(16)
    }

    private func openSystemPreferences(_ url: String) {
        guard let url = URL(string: url) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openTranscriptsFolder() {
        let dir = transcriptsDirectory()
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        NSWorkspace.shared.open(dir)
    }

    private func clearTranscripts() {
        let dir = transcriptsDirectory()
        guard let items = try? FileManager.default
            .contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }
        for url in items {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func transcriptsDirectory() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        return base
            .appendingPathComponent("VoiceMiddle")
            .appendingPathComponent("Transcripts")
    }
}

import SwiftUI

/// Step 2 of the onboarding wizard. Lists the environment variables
/// VoiceMiddle reads at launch and shows whether each one is currently
/// set. The user sets them in their shell config; this step verifies
/// they're visible to VoiceMiddle's process.
struct APIKeysStep: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("API keys")
                .font(.title2).bold()
            Text(
                "VoiceMiddle reads provider keys from environment"
                + " variables at launch. Set them in your shell config"
                + " (~/.zshrc, ~/.zprofile, etc.) so they're available to"
                + " every session."
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                keyRow(
                    name: "ELEVENLABS_API_KEY",
                    present: viewModel.elevenLabsKeyPresent,
                    requirement: .required
                )
                keyRow(
                    name: "DEEPL_API_KEY",
                    present: viewModel.deepLKeyPresent,
                    requirement: .requiredWhen("DeepL is the translator (default)")
                )
                keyRow(
                    name: "ANTHROPIC_API_KEY",
                    present: viewModel.anthropicKeyPresent,
                    requirement: .optional("for Claude translator")
                )
                keyRow(
                    name: "OPENAI_API_KEY",
                    present: viewModel.openAIKeyPresent,
                    requirement: .optional("future use")
                )
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text("Example").font(.headline)
                Text(
                    "export ELEVENLABS_API_KEY=\"sk_...\"\n"
                    + "export DEEPL_API_KEY=\"...\""
                )
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.12))
                )
            }

            HStack {
                Text(
                    "You may need to restart VoiceMiddle (from your"
                    + " terminal) for new env vars to take effect."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Re-check") { viewModel.refreshAll() }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { viewModel.refreshAll() }
    }

    // MARK: - Row

    private enum Requirement {
        case required
        case requiredWhen(String)
        case optional(String)
    }

    private func keyRow(
        name: String,
        present: Bool,
        requirement: Requirement
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(
                systemName: present
                    ? "checkmark.circle.fill"
                    : "xmark.circle"
            )
            .foregroundStyle(present ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(.body, design: .monospaced))
                Text(requirementDescription(requirement))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(present ? "Set" : "Not set")
                .font(.callout)
                .foregroundStyle(present ? .green : .secondary)
        }
    }

    private func requirementDescription(_ req: Requirement) -> String {
        switch req {
        case .required:
            return "Required."
        case .requiredWhen(let context):
            return "Required when \(context)."
        case .optional(let context):
            return "Optional — \(context)."
        }
    }
}

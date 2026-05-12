import SwiftUI

/// Placeholder. Translation-engine pickers, glossary, and read-only
/// inbound switch land in Task 4.3.
struct TranslationTab: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Translation")
                .font(.title2).bold()
            Text(
                "Translation engine, glossary, and read-only inbound "
                + "settings land in Task 4.3."
            )
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

import SwiftUI

/// Placeholder. Source / target language pickers and voice preview land
/// in Task 4.2.
struct LanguagesTab: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Languages")
                .font(.title2).bold()
            Text(
                "Source / target language pickers + voice preview land "
                + "in Task 4.2."
            )
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

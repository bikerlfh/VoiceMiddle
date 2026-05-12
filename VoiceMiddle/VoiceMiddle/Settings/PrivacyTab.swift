import SwiftUI

/// Placeholder. Telemetry, transcript-retention, and "clear all data"
/// controls land in Task 4.5.
struct PrivacyTab: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Privacy")
                .font(.title2).bold()
            Text(
                "Telemetry, transcript retention, and \"clear all data\" "
                + "controls land in Task 4.5."
            )
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

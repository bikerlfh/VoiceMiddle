import SwiftUI

/// Horizontal audio level bar, like a microphone-test indicator.
///
/// `level` is an RMS amplitude in `[0, 1]`. The bar fills proportionally and
/// shifts color from green (quiet) → yellow (loud) → red (peaking) so the
/// user can tell at a glance whether audio is actually being captured.
struct LevelMeter: View {
    let label: String
    let level: Float

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption)
                Spacer()
                Text(String(format: "%.0f%%", clamped * 100))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .foregroundStyle(.quaternary)
                    RoundedRectangle(cornerRadius: 3)
                        .foregroundStyle(meterColor)
                        .frame(
                            width: geometry.size.width * CGFloat(clamped)
                        )
                        .animation(
                            .linear(duration: 0.05), value: clamped
                        )
                }
            }
            .frame(height: 10)
        }
    }

    private var clamped: Float {
        max(0, min(1, level))
    }

    private var meterColor: Color {
        if clamped > 0.85 { return .red }
        if clamped > 0.5  { return .yellow }
        return .green
    }
}

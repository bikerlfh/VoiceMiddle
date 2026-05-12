import SwiftUI
import VMCore
import VMPipeline

/// SwiftUI content of the transcript HUD. Renders the rows published by
/// ``HUDViewModel`` and auto-scrolls to the newest entry as it arrives.
struct HUDView: View {
    @ObservedObject var model: HUDViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(model.rows, id: \.id) { row in
                        rowView(row).id(row.id)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.clear)
            .onChange(of: model.rows.count) { _, _ in
                if let last = model.rows.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(minWidth: 360, minHeight: 240)
    }

    @ViewBuilder
    private func rowView(_ row: HUDViewModel.Row) -> some View {
        switch row {
        case .turn(let turn):
            turnRow(turn)
        case .error(_, let direction, let message, let timestamp):
            errorRow(
                direction: direction,
                message: message,
                timestamp: timestamp
            )
        }
    }

    @ViewBuilder
    private func turnRow(_ turn: HUDViewModel.Turn) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(turn.direction == .inbound ? "\u{1F5E3} OTHER" : "\u{1F399} ME")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(Self.timeFormatter.string(from: turn.timestamp))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if turn.isInProgress {
                    Text("\u{2026} in progress")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Text(turn.original)
                .font(.body)
                .foregroundStyle(.secondary)
            if !turn.translated.isEmpty {
                Text("\u{2192} " + turn.translated)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func errorRow(
        direction: Direction,
        message: String,
        timestamp: Date
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("\u{26A0}")
                Text(direction == .inbound ? "OTHER" : "ME")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(Self.timeFormatter.string(from: timestamp))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(message)
                .font(.body)
                .foregroundStyle(.red)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

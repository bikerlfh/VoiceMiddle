import Combine
import Foundation
import SwiftUI
import VMCore
import VMPipeline

/// View-model backing ``HUDView``. Consumes ``TranscriptEvent`` values from
/// any number of pipelines and collapses partial events of the same
/// direction into a single in-progress row, so the HUD updates in place
/// rather than appending dozens of intermediate transcripts.
@MainActor
final class HUDViewModel: ObservableObject {
    struct Turn: Identifiable, Hashable {
        let id = UUID()
        let direction: Direction
        let original: String
        let translated: String
        let timestamp: Date
        var isInProgress: Bool
    }

    enum Row: Identifiable, Hashable {
        case turn(Turn)
        case error(
            id: UUID,
            direction: Direction,
            message: String,
            timestamp: Date
        )

        var id: AnyHashable {
            switch self {
            case .turn(let t):
                return AnyHashable(t.id)
            case .error(let id, _, _, _):
                return AnyHashable(id)
            }
        }
    }

    @Published private(set) var rows: [Row] = []
    private static let maxRows = 200

    /// Feed an event from a pipeline. Safe to call from `@MainActor`
    /// contexts only.
    func accept(_ event: TranscriptEvent) {
        switch event {
        case .partial(let direction, let original):
            updateOrAppendPartial(
                direction: direction,
                original: original
            )
        case .final(let direction, let original, let translated):
            replacePartialOrAppendFinal(
                direction: direction,
                original: original,
                translated: translated
            )
        case .error(let direction, let message):
            rows.append(.error(
                id: UUID(),
                direction: direction,
                message: message,
                timestamp: Date()
            ))
            trim()
        }
    }

    func clear() { rows.removeAll() }

    private func updateOrAppendPartial(
        direction: Direction,
        original: String
    ) {
        if case .turn(let last) = rows.last,
           last.direction == direction,
           last.isInProgress {
            let updated = Turn(
                direction: direction,
                original: original,
                translated: "",
                timestamp: last.timestamp,
                isInProgress: true
            )
            rows[rows.count - 1] = .turn(updated)
            return
        }
        rows.append(.turn(Turn(
            direction: direction,
            original: original,
            translated: "",
            timestamp: Date(),
            isInProgress: true
        )))
        trim()
    }

    private func replacePartialOrAppendFinal(
        direction: Direction,
        original: String,
        translated: String
    ) {
        if case .turn(let last) = rows.last,
           last.direction == direction,
           last.isInProgress {
            rows[rows.count - 1] = .turn(Turn(
                direction: direction,
                original: original,
                translated: translated,
                timestamp: last.timestamp,
                isInProgress: false
            ))
            return
        }
        rows.append(.turn(Turn(
            direction: direction,
            original: original,
            translated: translated,
            timestamp: Date(),
            isInProgress: false
        )))
        trim()
    }

    private func trim() {
        if rows.count > Self.maxRows {
            rows.removeFirst(rows.count - Self.maxRows)
        }
    }
}

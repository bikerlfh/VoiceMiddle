import Combine
import Foundation
import MetricKit

/// On-disk store for MetricKit diagnostic payloads.
///
/// MetricKit hands the app `MXDiagnosticPayload` instances on the next launch
/// after a crash. The store serialises each payload to JSON under
/// `~/Library/Application Support/VoiceMiddle/CrashReports/` so the user can
/// inspect or share it later from the Diagnostics window. Nothing is uploaded
/// anywhere — the MVP only persists locally.
@MainActor
final class CrashReportStore: ObservableObject {
    @Published private(set) var reports: [URL] = []
    let directory: URL

    init(directory: URL = CrashReportStore.defaultDirectory()) {
        self.directory = directory
        refresh()
    }

    nonisolated static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        return base
            .appendingPathComponent("VoiceMiddle")
            .appendingPathComponent("CrashReports")
    }

    /// Persists ``payload`` as a JSON file named with an ISO-8601 timestamp.
    /// Failures are swallowed because the app cannot do anything actionable
    /// if disk writes start failing inside a post-crash callback.
    func write(payload: MXDiagnosticPayload) {
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        let filename = "diag-\(ISO8601DateFormatter().string(from: Date())).json"
        let url = directory.appendingPathComponent(filename)
        try? payload.jsonRepresentation().write(to: url)
        refresh()
    }

    /// Removes every file currently in the crash-report directory.
    func clearAll() {
        guard
            let items = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
            )
        else { return }
        for url in items {
            try? FileManager.default.removeItem(at: url)
        }
        refresh()
    }

    /// Re-reads the report directory. Cheap enough to call on every write.
    func refresh() {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        reports = items.sorted {
            $0.lastPathComponent > $1.lastPathComponent
        }
    }
}

import Foundation
import MetricKit

/// Bridges `MXMetricManager` callbacks (called by the OS on launch after a
/// crash) into ``CrashReportStore`` writes.
///
/// `MXMetricManagerSubscriber` is an Objective-C protocol whose callbacks run
/// on an arbitrary queue, so the subscriber hops back to `@MainActor` before
/// touching the store's `@Published` state.
final class CrashReportSubscriber: NSObject, MXMetricManagerSubscriber {
    let store: CrashReportStore

    init(store: CrashReportStore) {
        self.store = store
        super.init()
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let store = self.store
        Task { @MainActor in
            for payload in payloads {
                store.write(payload: payload)
            }
        }
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        // Metric payloads (CPU/energy/etc.) are not used in the MVP.
    }
}

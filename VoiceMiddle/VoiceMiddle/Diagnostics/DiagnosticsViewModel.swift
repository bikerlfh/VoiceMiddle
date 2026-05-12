import AppKit
import Combine
import Foundation
import SwiftUI
import VMPipeline

/// View-model backing ``DiagnosticsView``. Polls a shared ``PipelineMetrics``
/// actor at a fixed rate so the UI can render a value-type snapshot without
/// awaiting from the view body. Surfaces the active ``SessionDriver``'s
/// recent error list verbatim and forwards the ``CrashReportStore``'s
/// ``reports`` list so the user can manage MetricKit diagnostics from the
/// same window.
@MainActor
final class DiagnosticsViewModel: ObservableObject {
    @Published private(set) var snapshot: PipelineMetrics.Snapshot = .empty
    @Published var refreshHz: Double = 2

    let crashReportStore: CrashReportStore
    private let metrics: PipelineMetrics
    private let driver: SessionDriver
    private var task: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init(
        metrics: PipelineMetrics,
        driver: SessionDriver,
        crashReportStore: CrashReportStore
    ) {
        self.metrics = metrics
        self.driver = driver
        self.crashReportStore = crashReportStore
        // Forward driver's recentErrors changes so SwiftUI re-renders this
        // view-model when the underlying SessionDriver publishes new ones.
        driver.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        // Same idea for the crash report store so the section updates when
        // a payload arrives or the user clears the list.
        crashReportStore.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    func start() {
        task?.cancel()
        let metrics = self.metrics
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let hz = max(self.refreshHz, 0.1)
                let interval = UInt64(1_000_000_000 / hz)
                self.snapshot = await metrics.snapshot()
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func reset() {
        let metrics = self.metrics
        Task { await metrics.reset() }
    }

    var recentErrors: [TranscriptEvent] { driver.recentErrors }

    var crashReports: [URL] { crashReportStore.reports }

    func clearCrashReports() {
        crashReportStore.clearAll()
    }

    func openCrashReportFolder() {
        let directory = crashReportStore.directory
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        NSWorkspace.shared.open(directory)
    }
}

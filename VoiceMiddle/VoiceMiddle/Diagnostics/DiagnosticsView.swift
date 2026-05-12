import SwiftUI
import VMPipeline

/// Renders the Diagnostics window contents. Shows live counters and EMA
/// latencies from the shared ``PipelineMetrics`` actor, recent pipeline
/// errors from the active ``SessionDriver``, and a Reset button.
struct DiagnosticsView: View {
    @ObservedObject var model: DiagnosticsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("VoiceMiddle Diagnostics")
                .font(.title2)
                .bold()

            GroupBox("Counters") {
                Grid(alignment: .leading) {
                    row(
                        "STT reconnects",
                        "\(model.snapshot.sttReconnects)"
                    )
                    row(
                        "Translator errors",
                        "\(model.snapshot.translatorErrors)"
                    )
                    row(
                        "TTS errors",
                        "\(model.snapshot.ttsErrors)"
                    )
                    row(
                        "End-to-end samples",
                        "\(model.snapshot.sampleCount)"
                    )
                }
                .padding(8)
            }

            GroupBox("Latencies (EMA)") {
                Grid(alignment: .leading) {
                    row(
                        "STT round-trip",
                        ms(model.snapshot.sttLatencyMs)
                    )
                    row(
                        "Translator",
                        ms(model.snapshot.translatorLatencyMs)
                    )
                    row(
                        "TTS time-to-first-chunk",
                        ms(model.snapshot.ttsTimeToFirstChunkMs)
                    )
                    row(
                        "End-to-end",
                        ms(model.snapshot.endToEndLatencyMs)
                    )
                }
                .padding(8)
            }

            GroupBox("Recent errors") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(
                            0..<model.recentErrors.count, id: \.self
                        ) { index in
                            errorRow(model.recentErrors[index])
                        }
                    }
                    .padding(8)
                }
                .frame(minHeight: 120)
            }

            GroupBox("Crash reports") {
                VStack(alignment: .leading, spacing: 8) {
                    if model.crashReports.isEmpty {
                        Text("No crash reports on disk.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(
                                    model.crashReports, id: \.self
                                ) { url in
                                    Text(url.lastPathComponent)
                                        .font(
                                            .system(
                                                .caption,
                                                design: .monospaced
                                            )
                                        )
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(minHeight: 60, maxHeight: 100)
                    }
                    HStack {
                        Button("Open folder") {
                            model.openCrashReportFolder()
                        }
                        Button("Clear all") {
                            model.clearCrashReports()
                        }
                        .disabled(model.crashReports.isEmpty)
                    }
                }
                .padding(8)
            }

            HStack {
                Button("Reset metrics") { model.reset() }
                Spacer()
                Text(
                    String(
                        format: "Refresh: %.0f Hz", model.refreshHz
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(minWidth: 480, minHeight: 480)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).font(.system(.body, design: .monospaced))
        }
    }

    @ViewBuilder
    private func errorRow(_ event: TranscriptEvent) -> some View {
        if case .error(_, let message) = event {
            Text(message)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.red)
        }
    }

    private func ms(_ value: Double) -> String {
        value > 0 ? String(format: "%.0f ms", value) : "\u{2014}"
    }
}

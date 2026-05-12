import Foundation
import VMCore
import VMPipeline

/// Persists ``TranscriptEvent`` values produced by a live session to a
/// JSON-Lines file under `~/Library/Application Support/VoiceMiddle/
/// Transcripts/<session>.jsonl`.
///
/// One record per line keeps appends cheap and crash-tolerant — partially
/// flushed sessions remain valid (each newline-terminated record is its own
/// JSON object).
@MainActor
final class TranscriptWriter {
    private let directory: URL
    private let sessionID = UUID()
    private var fileHandle: FileHandle?
    private let encoder = JSONEncoder()

    init(directory: URL = TranscriptWriter.defaultDirectory()) {
        self.directory = directory
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
    }

    /// `~/Library/Application Support/VoiceMiddle/Transcripts/`.
    nonisolated static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        return base
            .appendingPathComponent("VoiceMiddle")
            .appendingPathComponent("Transcripts")
    }

    /// Creates the destination directory if needed and opens the session
    /// file for append.
    func start() throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent(
            "\(sessionID).jsonl"
        )
        FileManager.default.createFile(atPath: url.path, contents: nil)
        fileHandle = try FileHandle(forWritingTo: url)
    }

    /// Appends one record per event. Errors are swallowed: a failure to
    /// persist a transcript line should not interrupt the live session.
    func append(_ event: TranscriptEvent) {
        guard let fh = fileHandle,
              let payload = try? encoder.encode(serialize(event))
        else { return }
        fh.write(payload)
        fh.write(Data("\n".utf8))
    }

    func close() {
        try? fileHandle?.close()
        fileHandle = nil
    }

    // MARK: - Wire format

    private struct Record: Codable {
        let type: String
        let direction: String
        let original: String?
        let translated: String?
        let message: String?
        let timestamp: Date
    }

    private func serialize(_ event: TranscriptEvent) -> Record {
        let now = Date()
        switch event {
        case .partial(let direction, let original):
            return Record(
                type: "partial",
                direction: direction.rawValue,
                original: original,
                translated: nil,
                message: nil,
                timestamp: now
            )
        case .final(let direction, let original, let translated):
            return Record(
                type: "final",
                direction: direction.rawValue,
                original: original,
                translated: translated,
                message: nil,
                timestamp: now
            )
        case .error(let direction, let message):
            return Record(
                type: "error",
                direction: direction.rawValue,
                original: nil,
                translated: nil,
                message: message,
                timestamp: now
            )
        }
    }
}

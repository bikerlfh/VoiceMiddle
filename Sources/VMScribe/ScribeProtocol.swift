import Foundation
import VMCore

/// Wire framing for the Scribe v2 realtime WebSocket.
///
/// Encoded shape (subject to revision when integrating against the real
/// ElevenLabs endpoint):
/// - Client → server: one JSON `start` text frame, then binary PCM frames of
///   little-endian Float32 samples, then a JSON `end_of_utterance` text frame.
/// - Server → client: JSON text frames carrying `partial`, `final`, or
///   `error` payloads.
enum ScribeProtocol {
    enum Inbound: Equatable, Sendable {
        case partial(text: String)
        case final(text: String)
        case error(message: String)
    }

    static func encodeStart(sampleRate: Int, language: LanguageCode) -> Data {
        let payload: [String: Any] = [
            "type": "start",
            "sample_rate": sampleRate,
            "encoding": "pcm_f32",
            "language": language.rawValue,
        ]
        // `try!` is justified: the dictionary contains only `String` and
        // `Int` values, which `JSONSerialization` is guaranteed to serialize.
        // A throw would indicate a programmer error and crashing is correct.
        return try! JSONSerialization.data(
            withJSONObject: payload, options: [.sortedKeys])
    }

    static func encodeEndOfUtterance() -> Data {
        let payload: [String: Any] = ["type": "end_of_utterance"]
        return try! JSONSerialization.data(
            withJSONObject: payload, options: [.sortedKeys])
    }

    /// Copies `count` Float32 samples into a freshly allocated `Data`.
    ///
    /// Allocates `count * MemoryLayout<Float>.size` bytes; this is the
    /// unavoidable cost of crossing the WebSocket transport boundary.
    static func encodePCM(
        _ samples: UnsafePointer<Float>, count: Int
    ) -> Data {
        let byteCount = count * MemoryLayout<Float>.size
        return Data(bytes: samples, count: byteCount)
    }

    static func decode(_ data: Data) -> Inbound? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let dict = object as? [String: Any],
            let type = dict["type"] as? String
        else { return nil }
        switch type {
        case "partial":
            guard let text = dict["text"] as? String else { return nil }
            return .partial(text: text)
        case "final":
            guard let text = dict["text"] as? String else { return nil }
            return .final(text: text)
        case "error":
            guard let message = dict["message"] as? String else { return nil }
            return .error(message: message)
        default:
            return nil
        }
    }
}

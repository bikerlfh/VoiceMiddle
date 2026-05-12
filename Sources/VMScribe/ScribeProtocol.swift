import Foundation
import VMCore

/// Wire framing for the ElevenLabs Scribe v2 realtime WebSocket.
///
/// All client→server and server→client messages are JSON text frames with a
/// `message_type` discriminator. Audio is base64-encoded Int16 little-endian
/// PCM at the negotiated sample rate (we use 48 kHz mono).
enum ScribeProtocol {
    enum Inbound: Equatable, Sendable {
        case sessionStarted(sessionID: String)
        case partial(text: String)
        case final(text: String)
        case error(kind: String, message: String)
    }

    /// Builds the WebSocket URL with required query parameters. The client
    /// adds the xi-api-key header at connect time.
    static func makeURL(
        baseURL: URL,
        sourceLanguage: LanguageCode
    ) -> URL {
        var components = URLComponents(
            url: baseURL, resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "model_id", value: "scribe_v2_realtime"),
            URLQueryItem(name: "audio_format", value: "pcm_48000"),
            URLQueryItem(name: "language_code",
                         value: sourceLanguage.primarySubtag),
            URLQueryItem(name: "commit_strategy", value: "vad"),
            URLQueryItem(name: "include_timestamps", value: "false"),
        ]
        return components.url!
    }

    /// Encodes one audio chunk for the wire. `samples` are Float32 in the
    /// range [-1, 1]; we convert to Int16 little-endian and base64 inside the
    /// JSON envelope.
    static func encodeAudioChunk(
        _ samples: UnsafePointer<Float>,
        count: Int,
        sampleRate: Int,
        commit: Bool
    ) -> Data {
        let base64 = base64EncodedInt16PCM(samples, count: count)
        let payload: [String: Any] = [
            "message_type": "input_audio_chunk",
            "audio_base_64": base64,
            "sample_rate": sampleRate,
            "commit": commit,
        ]
        // `try!` is justified: the dictionary contains only `String`, `Int`,
        // and `Bool` values, which `JSONSerialization` is guaranteed to
        // serialize. A throw would indicate a programmer error.
        return try! JSONSerialization.data(
            withJSONObject: payload, options: [.sortedKeys])
    }

    /// Encodes a zero-length chunk that just commits the in-flight utterance.
    static func encodeCommitOnly(sampleRate: Int) -> Data {
        let payload: [String: Any] = [
            "message_type": "input_audio_chunk",
            "audio_base_64": "",
            "sample_rate": sampleRate,
            "commit": true,
        ]
        return try! JSONSerialization.data(
            withJSONObject: payload, options: [.sortedKeys])
    }

    static func decode(_ data: Data) -> Inbound? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let dict = object as? [String: Any],
            let type = dict["message_type"] as? String
        else { return nil }
        switch type {
        case "session_started":
            return .sessionStarted(
                sessionID: dict["session_id"] as? String ?? ""
            )
        case "partial_transcript":
            guard let text = dict["text"] as? String else { return nil }
            return .partial(text: text)
        case "committed_transcript":
            guard let text = dict["text"] as? String else { return nil }
            return .final(text: text)
        default:
            // Treat any other message_type as an error variant — the docs
            // list 12 distinct error kinds, all carrying an "error" field.
            let message = (dict["error"] as? String) ?? type
            return .error(kind: type, message: message)
        }
    }

    // MARK: - PCM conversion

    /// Converts Float32 samples in [-1, 1] to Int16 little-endian bytes and
    /// returns the base64-encoded string. Clamps out-of-range floats.
    private static func base64EncodedInt16PCM(
        _ samples: UnsafePointer<Float>, count: Int
    ) -> String {
        guard count > 0 else { return "" }
        var bytes = Data(count: count * 2)
        bytes.withUnsafeMutableBytes { raw in
            let dst = raw.bindMemory(to: Int16.self)
            for i in 0..<count {
                let clamped = max(-1.0, min(1.0, samples[i]))
                dst[i] = Int16(clamped * Float(Int16.max))
            }
        }
        return bytes.base64EncodedString()
    }
}

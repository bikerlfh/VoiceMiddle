import Foundation

enum FlashProtocol {
    struct VoiceSettings: Hashable, Sendable {
        var stability: Double
        var similarityBoost: Double

        static let `default` = VoiceSettings(
            stability: 0.5, similarityBoost: 0.75
        )
    }

    enum Inbound: Hashable, Sendable {
        case chunk(Data)
        case end
    }

    static func encodeInit(
        apiKey: String, voiceSettings: VoiceSettings
    ) -> Data {
        let payload: [String: Any] = [
            "xi_api_key": apiKey,
            "voice_settings": [
                "stability": voiceSettings.stability,
                "similarity_boost": voiceSettings.similarityBoost,
            ],
        ]
        return try! JSONSerialization.data(
            withJSONObject: payload, options: [.sortedKeys])
    }

    static func encodeText(_ text: String) -> Data {
        let payload: [String: Any] = [
            "text": text,
            "try_trigger_generation": true,
        ]
        return try! JSONSerialization.data(
            withJSONObject: payload, options: [.sortedKeys])
    }

    static func encodeEndOfInput() -> Data {
        let payload: [String: Any] = ["text": ""]
        return try! JSONSerialization.data(
            withJSONObject: payload, options: [.sortedKeys])
    }

    static func decode(_ data: Data) -> Inbound? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let dict = object as? [String: Any]
        else { return nil }
        if let isFinal = dict["isFinal"] as? Bool, isFinal {
            return .end
        }
        if let audio = dict["audio"] as? String,
           let pcm = Data(base64Encoded: audio) {
            return .chunk(pcm)
        }
        return nil
    }
}

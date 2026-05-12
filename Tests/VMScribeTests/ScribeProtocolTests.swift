import Testing
import Foundation
import VMCore
@testable import VMScribe

@Suite("ScribeProtocol")
struct ScribeProtocolTests {
    @Test("URL builder appends required query params")
    func makeURL() throws {
        let url = ScribeProtocol.makeURL(
            baseURL: URL(string:
                "wss://api.elevenlabs.io/v1/speech-to-text/realtime"
            )!,
            sourceLanguage: try LanguageCode("en-US")
        )
        let components = try #require(
            URLComponents(url: url, resolvingAgainstBaseURL: false)
        )
        let pairs = (components.queryItems ?? []).map {
            ($0.name, $0.value ?? "")
        }
        let dict = Dictionary(uniqueKeysWithValues: pairs)
        #expect(dict["model_id"] == "scribe_v2_realtime")
        #expect(dict["audio_format"] == "pcm_48000")
        #expect(dict["language_code"] == "en")
        #expect(dict["commit_strategy"] == "manual")
        #expect(dict["include_timestamps"] == "false")
    }

    @Test("Audio chunk encodes input_audio_chunk with base64 PCM")
    func encodeAudioChunk() throws {
        let samples: [Float] = [0, 0.5, -0.5, 1.0]
        let data = samples.withUnsafeBufferPointer {
            ScribeProtocol.encodeAudioChunk(
                $0.baseAddress!, count: $0.count,
                sampleRate: 48_000, commit: false
            )
        }
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(json["message_type"] as? String == "input_audio_chunk")
        #expect(json["sample_rate"] as? Int == 48_000)
        #expect(json["commit"] as? Bool == false)
        let b64 = try #require(json["audio_base_64"] as? String)
        let bytes = try #require(Data(base64Encoded: b64))
        #expect(bytes.count == samples.count * 2)
        let int16s = bytes.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Int16.self))
        }
        // 0.0  → 0
        // 0.5  → 16383 ish
        // -0.5 → -16383 ish
        // 1.0  → Int16.max
        #expect(int16s[0] == 0)
        #expect(int16s[1] > 16_000 && int16s[1] < 17_000)
        #expect(int16s[2] < -16_000 && int16s[2] > -17_000)
        #expect(int16s[3] == Int16.max)
    }

    @Test("Commit-only chunk has empty base64 audio and commit=true")
    func encodeCommitOnly() throws {
        let data = ScribeProtocol.encodeCommitOnly(sampleRate: 48_000)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(json["audio_base_64"] as? String == "")
        #expect(json["commit"] as? Bool == true)
    }

    @Test("Decode dispatches partial, final, and error variants")
    func decodeVariants() throws {
        let partial = try #require(
            ScribeProtocol.decode(
                Data(#"{"message_type":"partial_transcript","text":"hi"}"#.utf8)
            )
        )
        if case .partial(let text) = partial {
            #expect(text == "hi")
        } else { Issue.record("Expected partial") }

        let final = try #require(
            ScribeProtocol.decode(
                Data(#"{"message_type":"committed_transcript","text":"done"}"#.utf8)
            )
        )
        if case .final(let text) = final {
            #expect(text == "done")
        } else { Issue.record("Expected final") }

        let err = try #require(
            ScribeProtocol.decode(
                Data(#"{"message_type":"auth_error","error":"bad key"}"#.utf8)
            )
        )
        if case .error(let kind, let message) = err {
            #expect(kind == "auth_error")
            #expect(message == "bad key")
        } else { Issue.record("Expected error") }
    }

    @Test("Decode handles session_started")
    func decodeSessionStarted() throws {
        let started = try #require(
            ScribeProtocol.decode(
                Data(#"{"message_type":"session_started","session_id":"abc"}"#.utf8)
            )
        )
        if case .sessionStarted(let id) = started {
            #expect(id == "abc")
        } else { Issue.record("Expected session_started") }
    }
}

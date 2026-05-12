import Testing
import Foundation
@testable import VMFlash

@Suite("FlashProtocol")
struct FlashProtocolTests {
    @Test("Init frame embeds api key and voice settings")
    func encodeInit() throws {
        let frame = FlashProtocol.encodeInit(
            apiKey: "k",
            voiceSettings: .default
        )
        let json = try #require(
            try JSONSerialization.jsonObject(with: frame) as? [String: Any]
        )
        #expect(json["xi_api_key"] as? String == "k")
        let voiceSettings = try #require(
            json["voice_settings"] as? [String: Any]
        )
        #expect((voiceSettings["stability"] as? Double) == 0.5)
        #expect((voiceSettings["similarity_boost"] as? Double) == 0.75)
    }

    @Test("Text frame includes try_trigger_generation")
    func encodeText() throws {
        let frame = FlashProtocol.encodeText("hello world")
        let json = try #require(
            try JSONSerialization.jsonObject(with: frame) as? [String: Any]
        )
        #expect(json["text"] as? String == "hello world")
        #expect((json["try_trigger_generation"] as? Bool) == true)
    }

    @Test("End-of-input frame is empty text")
    func encodeEnd() throws {
        let frame = FlashProtocol.encodeEndOfInput()
        let json = try #require(
            try JSONSerialization.jsonObject(with: frame) as? [String: Any]
        )
        #expect(json["text"] as? String == "")
    }

    @Test("Decode extracts base64 audio chunk")
    func decodeAudio() throws {
        let sample: [Float] = [0.1, 0.2, -0.3]
        let pcm = sample.withUnsafeBytes { Data($0) }
        let base64 = pcm.base64EncodedString()
        let frameText = #"{"audio":"\#(base64)","isFinal":false}"#
        let decoded = try #require(
            FlashProtocol.decode(Data(frameText.utf8))
        )
        if case .chunk(let data) = decoded {
            #expect(data == pcm)
        } else {
            Issue.record("Expected .chunk")
        }
    }

    @Test("Decode handles isFinal=true with no audio")
    func decodeFinal() throws {
        let decoded = try #require(
            FlashProtocol.decode(Data(#"{"isFinal":true}"#.utf8))
        )
        #expect(decoded == .end)
    }

    @Test("Decode returns nil for unrecognized frames")
    func decodeUnknown() {
        #expect(FlashProtocol.decode(Data(#"{"foo":"bar"}"#.utf8)) == nil)
    }
}

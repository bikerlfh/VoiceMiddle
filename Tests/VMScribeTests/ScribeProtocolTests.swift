import Testing
import Foundation
import VMCore
@testable import VMScribe

@Suite("ScribeProtocol")
struct ScribeProtocolTests {
    @Test("Start frame encodes sample rate, encoding, and language")
    func encodeStart() throws {
        let frame = ScribeProtocol.encodeStart(
            sampleRate: 48_000,
            language: try LanguageCode("en")
        )
        let json = try #require(
            try JSONSerialization.jsonObject(with: frame) as? [String: Any]
        )
        #expect(json["type"] as? String == "start")
        #expect(json["sample_rate"] as? Int == 48_000)
        #expect(json["encoding"] as? String == "pcm_f32")
        #expect(json["language"] as? String == "en")
    }

    @Test("End-of-utterance frame is the documented sentinel")
    func encodeEnd() throws {
        let frame = ScribeProtocol.encodeEndOfUtterance()
        let json = try #require(
            try JSONSerialization.jsonObject(with: frame) as? [String: Any]
        )
        #expect(json["type"] as? String == "end_of_utterance")
    }

    @Test("PCM frame encoder copies Float32 samples as little-endian bytes")
    func encodePCM() {
        let samples: [Float] = [0, 0.25, -0.5, 1.0]
        let data = samples.withUnsafeBufferPointer {
            ScribeProtocol.encodePCM($0.baseAddress!, count: $0.count)
        }
        #expect(data.count == samples.count * MemoryLayout<Float>.size)
        let roundTripped = data.withUnsafeBytes { raw -> [Float] in
            Array(raw.bindMemory(to: Float.self))
        }
        #expect(roundTripped == samples)
    }

    @Test("Decode dispatches to partial, final, and error variants")
    func decodeVariants() throws {
        let partial = try #require(
            ScribeProtocol.decode(
                Data(#"{"type":"partial","text":"hello"}"#.utf8)
            )
        )
        if case .partial(let text) = partial {
            #expect(text == "hello")
        } else {
            Issue.record("Expected partial")
        }

        let final = try #require(
            ScribeProtocol.decode(
                Data(#"{"type":"final","text":"hello world"}"#.utf8)
            )
        )
        if case .final(let text) = final {
            #expect(text == "hello world")
        } else {
            Issue.record("Expected final")
        }

        let error = try #require(
            ScribeProtocol.decode(
                Data(#"{"type":"error","message":"boom"}"#.utf8)
            )
        )
        if case .error(let message) = error {
            #expect(message == "boom")
        } else {
            Issue.record("Expected error")
        }
    }

    @Test("Unknown frame types decode to nil")
    func decodeUnknown() {
        let unknown = ScribeProtocol.decode(
            Data(#"{"type":"keep_alive"}"#.utf8)
        )
        #expect(unknown == nil)
    }
}

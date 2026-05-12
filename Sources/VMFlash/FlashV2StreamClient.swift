import Foundation
import VMCore

/// Streaming TTS over the ElevenLabs Flash v2.5 WebSocket.
///
/// Each ``synthesize(_:voice:sink:)`` invocation opens a fresh WebSocket
/// session for that utterance:
/// 1. Sends the init JSON (api key + voice settings).
/// 2. Sends the text payload with `try_trigger_generation: true`.
/// 3. Sends the empty-text end-of-input sentinel.
/// 4. Reads server frames, base64-decoding audio chunks and forwarding them
///    to the sink until `isFinal == true` arrives.
///
/// The client uses an injected ``WebSocketTransport`` so tests can run
/// against a deterministic fake.
public actor FlashV2StreamClient: TTSStreamClient {
    public struct Configuration: Hashable, Sendable {
        public var modelID: String
        public var outputFormat: String
        public var optimizeStreamingLatency: Int

        public static let `default` = Configuration(
            modelID: "eleven_flash_v2_5",
            outputFormat: "pcm_48000",
            optimizeStreamingLatency: 3
        )
    }

    private let apiKey: String
    private let baseURL: URL
    private let configuration: Configuration
    private let makeTransport: @Sendable () -> any WebSocketTransport

    public init(
        apiKey: String,
        baseURL: URL = URL(
            string: "wss://api.elevenlabs.io/v1/text-to-speech")!,
        configuration: Configuration = .default,
        makeTransport: @escaping @Sendable () -> any WebSocketTransport = {
            URLSessionWebSocketTransport()
        }
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.configuration = configuration
        self.makeTransport = makeTransport
    }

    public func synthesize(
        _ text: String,
        voice: VoiceID,
        sink: @escaping @Sendable (Data) -> Void
    ) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TTSError.empty }

        let transport = makeTransport()
        let url = endpoint(forVoice: voice)

        do {
            try await transport.connect(url: url, headers: [
                "xi-api-key": apiKey,
            ])
        } catch {
            throw TTSError.transport(message: error.localizedDescription)
        }

        do {
            try await sendText(transport: transport,
                               data: FlashProtocol.encodeInit(
                                apiKey: apiKey,
                                voiceSettings: .default))
            try await sendText(transport: transport,
                               data: FlashProtocol.encodeText(trimmed))
            try await sendText(transport: transport,
                               data: FlashProtocol.encodeEndOfInput())
        } catch {
            await transport.close()
            throw TTSError.transport(message: error.localizedDescription)
        }

        do {
            try await readLoop(transport: transport, sink: sink)
        } catch let e as TTSError {
            await transport.close()
            throw e
        } catch {
            await transport.close()
            throw TTSError.transport(message: error.localizedDescription)
        }

        await transport.close()
    }

    private func sendText(
        transport: any WebSocketTransport, data: Data
    ) async throws {
        guard let s = String(data: data, encoding: .utf8) else { return }
        try await transport.sendText(s)
    }

    private func readLoop(
        transport: any WebSocketTransport,
        sink: @Sendable (Data) -> Void
    ) async throws {
        while true {
            guard let frame = try await transport.receive() else {
                return
            }
            switch frame {
            case .binary:
                continue
            case .text(let s):
                guard let data = s.data(using: .utf8),
                      let inbound = FlashProtocol.decode(data) else {
                    throw TTSError.decode
                }
                switch inbound {
                case .chunk(let pcm):
                    sink(pcm)
                case .end:
                    return
                }
            }
        }
    }

    private func endpoint(forVoice voice: VoiceID) -> URL {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(voice.rawValue)
                .appendingPathComponent("stream-input"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "model_id",
                         value: configuration.modelID),
            URLQueryItem(name: "output_format",
                         value: configuration.outputFormat),
            URLQueryItem(name: "optimize_streaming_latency",
                         value: "\(configuration.optimizeStreamingLatency)"),
        ]
        return components.url!
    }
}

@preconcurrency import AVFoundation
import Foundation
import VMCore

/// Realtime STT client for ElevenLabs Scribe v2.
///
/// Uses a pluggable ``WebSocketTransport`` so tests can inject a deterministic
/// fake. Production code constructs the client with a default
/// ``URLSessionWebSocketTransport``.
///
/// Wire framing is delegated to ``ScribeProtocol``: connection parameters
/// (model, sample rate, language, commit strategy) are carried as query
/// items on the URL; audio chunks travel as JSON text frames carrying
/// base64-encoded Int16 little-endian PCM. Authentication is the
/// `xi-api-key` request header.
///
/// Reconnect with exponential backoff is intentionally deferred to the
/// pipeline orchestrator: `connect()` is idempotent and callable after a
/// transport failure, but this actor does not loop on its own.
public actor ScribeV2StreamClient: STTStreamClient {
    private let baseURL: URL
    private let apiKey: String
    private let sourceLanguage: LanguageCode
    private let transport: any WebSocketTransport

    private let partialsContinuation: AsyncStream<String>.Continuation
    private let finalsContinuation: AsyncStream<String>.Continuation
    private let errorsContinuation: AsyncStream<STTError>.Continuation

    private var readerTask: Task<Void, Never>?
    private var isConnected = false

    public nonisolated let partials: AsyncStream<String>
    public nonisolated let finals: AsyncStream<String>
    public nonisolated let errors: AsyncStream<STTError>

    public init(
        url: URL = URL(
            string: "wss://api.elevenlabs.io/v1/speech-to-text/realtime"
        )!,
        apiKey: String,
        sourceLanguage: LanguageCode,
        transport: any WebSocketTransport = URLSessionWebSocketTransport()
    ) {
        self.baseURL = url
        self.apiKey = apiKey
        self.sourceLanguage = sourceLanguage
        self.transport = transport

        var pc: AsyncStream<String>.Continuation!
        self.partials = AsyncStream { pc = $0 }
        var fc: AsyncStream<String>.Continuation!
        self.finals = AsyncStream { fc = $0 }
        var ec: AsyncStream<STTError>.Continuation!
        self.errors = AsyncStream { ec = $0 }

        self.partialsContinuation = pc
        self.finalsContinuation = fc
        self.errorsContinuation = ec
    }

    public func connect() async {
        guard !isConnected else { return }
        let endpoint = ScribeProtocol.makeURL(
            baseURL: baseURL,
            sourceLanguage: sourceLanguage
        )
        do {
            try await transport.connect(
                url: endpoint,
                headers: ["xi-api-key": apiKey]
            )
            isConnected = true
            startReader()
        } catch {
            errorsContinuation.yield(
                .transport(message: error.localizedDescription)
            )
        }
    }

    private func startReader() {
        readerTask?.cancel()
        readerTask = Task { [weak self] in
            await self?.readLoop()
        }
    }

    private func readLoop() async {
        while !Task.isCancelled, isConnected {
            do {
                guard let frame = try await transport.receive() else { break }
                handleFrame(frame)
            } catch {
                errorsContinuation.yield(
                    .transport(message: error.localizedDescription)
                )
                isConnected = false
                break
            }
        }
    }

    private func handleFrame(_ frame: WebSocketFrame) {
        switch frame {
        case .binary:
            return    // Scribe v2 only emits JSON text frames.
        case .text(let s):
            guard let data = s.data(using: .utf8),
                  let inbound = ScribeProtocol.decode(data) else {
                errorsContinuation.yield(.decode)
                return
            }
            switch inbound {
            case .sessionStarted:
                return
            case .partial(let text):
                partialsContinuation.yield(text)
            case .final(let text):
                finalsContinuation.yield(text)
            case .error(_, let message):
                errorsContinuation.yield(.server(message: message))
            }
        }
    }

    public func send(_ pcm: AVAudioPCMBuffer) async {
        guard isConnected,
              let channelData = pcm.floatChannelData?[0] else { return }
        let count = Int(pcm.frameLength)
        let data = ScribeProtocol.encodeAudioChunk(
            channelData, count: count,
            sampleRate: Int(CanonicalAudioFormat.sampleRate),
            commit: false
        )
        guard let s = String(data: data, encoding: .utf8) else { return }
        do {
            try await transport.sendText(s)
        } catch {
            errorsContinuation.yield(
                .transport(message: error.localizedDescription)
            )
        }
    }

    public func flushUtterance() async {
        guard isConnected else { return }
        let data = ScribeProtocol.encodeCommitOnly(
            sampleRate: Int(CanonicalAudioFormat.sampleRate)
        )
        guard let s = String(data: data, encoding: .utf8) else { return }
        do {
            try await transport.sendText(s)
        } catch {
            errorsContinuation.yield(
                .transport(message: error.localizedDescription)
            )
        }
    }

    public func close() async {
        readerTask?.cancel()
        readerTask = nil
        await transport.close()
        isConnected = false
    }
}

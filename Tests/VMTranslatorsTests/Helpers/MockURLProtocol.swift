import Foundation

/// A `URLProtocol` subclass that records every incoming request and returns
/// pre-registered responses keyed by URL host.
///
/// Tests register a handler with `MockURLProtocol.handler = { request in ... }`
/// and configure a `URLSession` with this protocol class via
/// `URLSessionConfiguration.ephemeral`.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler:
        (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    nonisolated(unsafe) private(set) static var capturedRequests:
        [URLRequest] = []

    static func reset() {
        handler = nil
        capturedRequests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for r: URLRequest) -> URLRequest {
        r
    }

    override func startLoading() {
        // URLSession may move small bodies into `httpBody` and larger ones
        // into `httpBodyStream` before the protocol sees the request. Tests
        // want a single, uniform place to read the body from, so drain any
        // stream into `httpBody` on a request copy that we capture.
        var captured = request
        if captured.httpBody == nil, let stream = captured.httpBodyStream {
            captured.httpBody = Self.readAll(stream)
        }
        Self.capturedRequests.append(captured)
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(
                self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func readAll(_ stream: InputStream) -> Data {
        stream.open(); defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 4096)
        var data = Data()
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}

/// Builds a `URLSession` whose requests are intercepted by ``MockURLProtocol``.
func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

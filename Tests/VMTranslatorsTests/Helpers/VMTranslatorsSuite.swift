import Testing

/// Parent suite for all translator tests. Marked `.serialized` so that the
/// child suites — which share the global `MockURLProtocol` handler — never
/// run in parallel and stomp on each other's captured requests.
@Suite("VMTranslators", .serialized)
enum VMTranslatorsSuite {}

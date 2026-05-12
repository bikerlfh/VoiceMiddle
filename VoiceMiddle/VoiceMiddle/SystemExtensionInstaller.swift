import Foundation
import SystemExtensions
import os

/// Wraps `OSSystemExtensionManager` for activating the bundled VoiceMiddle
/// audio driver System Extension.
///
/// The installer is an `actor` so its state is serialized across UI taps and
/// async callbacks. State is exposed via the ``status`` property and an
/// `AsyncStream` of transitions for SwiftUI views to observe.
public actor SystemExtensionInstaller {
    public enum Status: Hashable, Sendable {
        case unknown
        case notInstalled
        case needsApproval
        case installing
        case installed
        case failed(message: String)
    }

    public private(set) var status: Status = .unknown

    private let driverBundleID: String
    private let logger = Logger(subsystem: "com.luismo.voicemiddle",
                                category: "driver-installer")
    private var continuations: [UUID: AsyncStream<Status>.Continuation] = [:]
    private var pendingRequest: PendingRequest?

    public init(driverBundleID: String) {
        self.driverBundleID = driverBundleID
    }

    public var statuses: AsyncStream<Status> {
        AsyncStream { continuation in
            let id = UUID()
            continuation.yield(self.status)
            self.continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id: id) }
            }
        }
    }

    /// Submits an activation request for the driver. Resolves when the system
    /// reports completion (approved/failed/needsApproval). Multiple concurrent
    /// callers wait on the same request.
    public func install() async throws {
        if let pending = pendingRequest {
            try await pending.task.value
            return
        }
        update(.installing)
        let pending = PendingRequest()
        pendingRequest = pending
        do {
            try await runActivation(pending: pending)
            pendingRequest = nil
        } catch {
            pendingRequest = nil
            throw error
        }
    }

    private func runActivation(pending: PendingRequest) async throws {
        let bundleID = driverBundleID
        let delegate = Delegate(installer: self, pending: pending)

        // Submit the request on the main queue (Apple's API expects it).
        await MainActor.run {
            let request = OSSystemExtensionRequest.activationRequest(
                forExtensionWithIdentifier: bundleID,
                queue: .main
            )
            request.delegate = delegate
            // Retain the delegate for the lifetime of the request.
            pending.delegate = delegate
            OSSystemExtensionManager.shared.submitRequest(request)
            self.logger.info("Submitted activation request for \(bundleID, privacy: .public)")
        }

        try await pending.task.value
    }

    fileprivate func update(_ next: Status) {
        status = next
        for continuation in continuations.values { continuation.yield(next) }
    }

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    /// Holds the in-flight request's continuation and the delegate keeping it
    /// alive. `Sendable` because the continuation is itself thread-safe and
    /// the delegate is hopped onto the main actor before being touched.
    fileprivate final class PendingRequest: @unchecked Sendable {
        let task: Task<Void, Error>
        var delegate: NSObject?
        private let continuation: CheckedContinuation<Void, Error>

        init() {
            var capturedContinuation: CheckedContinuation<Void, Error>!
            self.task = Task<Void, Error> {
                try await withCheckedThrowingContinuation { c in
                    capturedContinuation = c
                }
            }
            self.continuation = capturedContinuation
        }

        func succeed() { continuation.resume() }
        func fail(_ error: Error) { continuation.resume(throwing: error) }
    }

    fileprivate final class Delegate: NSObject,
                                      OSSystemExtensionRequestDelegate {
        unowned let installer: SystemExtensionInstaller
        let pending: PendingRequest

        init(installer: SystemExtensionInstaller, pending: PendingRequest) {
            self.installer = installer
            self.pending = pending
        }

        func request(_ request: OSSystemExtensionRequest,
                     actionForReplacingExtension existing: OSSystemExtensionProperties,
                     withExtension ext: OSSystemExtensionProperties)
        -> OSSystemExtensionRequest.ReplacementAction {
            .replace
        }

        func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
            Task { await self.installer.update(.needsApproval) }
        }

        func request(_ request: OSSystemExtensionRequest,
                     didFinishWithResult result: OSSystemExtensionRequest.Result) {
            switch result {
            case .completed:
                Task { await self.installer.update(.installed) }
                pending.succeed()
            case .willCompleteAfterReboot:
                Task { await self.installer.update(.installing) }
                pending.succeed()
            @unknown default:
                let message = "Unknown OSSystemExtensionRequest result"
                Task { await self.installer.update(.failed(message: message)) }
                pending.fail(NSError(
                    domain: "VoiceMiddle.SystemExtensionInstaller",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: message]
                ))
            }
        }

        func request(_ request: OSSystemExtensionRequest,
                     didFailWithError error: Error) {
            let message = error.localizedDescription
            Task { await self.installer.update(.failed(message: message)) }
            pending.fail(error)
        }
    }
}

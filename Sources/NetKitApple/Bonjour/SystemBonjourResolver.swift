import Foundation

// MARK: - SystemBonjourResolver

/// Production adapter wrapping ``NetService`` resolution with async/await.
///
/// ``NetService/resolve(withTimeout:)`` **must** run on a ``RunLoop``-pumped
/// thread. This implementation dispatches resolution to the main queue and
/// uses ``CheckedContinuation`` to bridge back to Swift Concurrency.
///
/// The ``ResolveHandler`` delegate is retained via ``objc_setAssociatedObject``
/// for the lifetime of the ``NetService``, preventing premature deallocation
/// under ARC before the delegate fires.
public final class SystemBonjourResolver: BonjourServiceResolving {

    public init() {}

    /// Resolve a ``BonjourServiceDescriptor`` to a fully-populated
    /// ``BonjourResolvedService``.
    ///
    /// - Parameters:
    ///   - service: Descriptor obtained from a ``BonjourNetworkBrowsingDelegate`` callback.
    ///   - timeout: Maximum seconds ``NetService`` may spend resolving.
    /// - Returns: Resolved service with host, port, and parsed TXT record.
    /// - Throws: ``BonjourDiscoveryError/resolutionTimeout`` on timeout or
    ///   delegate-reported failure.
    public func resolve(_ service: BonjourServiceDescriptor, timeout: TimeInterval) async throws -> BonjourResolvedService {
        try await withCheckedThrowingContinuation { continuation in
            // NetService.resolve MUST run on a RunLoop — dispatch to main.
            DispatchQueue.main.async {
                let netService = NetService(
                    domain: service.domain,
                    type: service.type,
                    name: service.name
                )
                let handler = ResolveHandler(name: service.name, continuation: continuation)
                netService.delegate = handler
                // Retain both directions so neither is released before the callback.
                objc_setAssociatedObject(netService, "handler", handler, .OBJC_ASSOCIATION_RETAIN)
                objc_setAssociatedObject(handler, "service", netService, .OBJC_ASSOCIATION_RETAIN)
                netService.schedule(in: .main, forMode: .common)
                netService.resolve(withTimeout: timeout)
            }
        }
    }
}

// MARK: - ResolveHandler

/// Internal ``NetServiceDelegate`` that bridges resolution callbacks to a
/// ``CheckedContinuation``.
///
/// The continuation is consumed exactly once — either on success
/// (``netServiceDidResolveAddress(_:)``) or on failure
/// (``netService(_:didNotResolve:)``).
private final class ResolveHandler: NSObject, NetServiceDelegate, @unchecked Sendable {

    private let name: String
    private var continuation: CheckedContinuation<BonjourResolvedService, any Error>?

    init(name: String, continuation: CheckedContinuation<BonjourResolvedService, any Error>) {
        self.name = name
        self.continuation = continuation
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let continuation else { return }
        self.continuation = nil

        let hostName = sender.hostName ?? "unknown"
        let port = sender.port

        var txtRecord: [String: String] = [:]
        if let data = sender.txtRecordData() {
            txtRecord = BonjourTXTRecord.parse(data)
        }

        let resolved = BonjourResolvedService(
            name: name,
            hostName: hostName,
            port: port,
            txtRecord: txtRecord
        )
        continuation.resume(returning: resolved)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(throwing: BonjourDiscoveryError.resolutionTimeout)
    }
}

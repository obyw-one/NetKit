import Foundation

// MARK: - BonjourNetworkBrowsing

/// Abstraction over ``NetServiceBrowser`` for testability.
///
/// The production implementation ``SystemBonjourBrowser`` wraps the real
/// ``NetServiceBrowser``. In tests, inject a ``MockBonjourBrowser`` (or any
/// conforming type) that fires delegate callbacks synchronously.
public protocol BonjourNetworkBrowsing: AnyObject, Sendable {

    /// The delegate that receives browse result callbacks.
    var browsingDelegate: (any BonjourNetworkBrowsingDelegate)? { get set }

    /// Begin searching for services of the given type in the given domain.
    ///
    /// - Parameters:
    ///   - type: Bonjour service type including trailing dot
    ///     (e.g. `"_shi-nats._tcp."`).
    ///   - domain: Search domain (e.g. `"local."`).
    func searchForServices(ofType type: String, inDomain domain: String)

    /// Stop the active search.
    func stop()
}

// MARK: - BonjourNetworkBrowsingDelegate

/// Delegate callbacks matching ``NetServiceBrowserDelegate`` semantics,
/// expressed in terms of NetKit types for protocol isolation.
public protocol BonjourNetworkBrowsingDelegate: AnyObject, Sendable {

    /// A service matching the search type was found on the network.
    ///
    /// - Parameters:
    ///   - service: Descriptor for the discovered service.
    ///   - moreComing: `true` when additional services are expected
    ///     imminently (batch discovery hint).
    func bonjourBrowser(didFind service: BonjourServiceDescriptor, moreComing: Bool)

    /// A previously found service is no longer available.
    ///
    /// - Parameters:
    ///   - service: Descriptor for the removed service.
    ///   - moreComing: `true` when additional removals are expected imminently.
    func bonjourBrowser(didRemove service: BonjourServiceDescriptor, moreComing: Bool)

    /// The browser stopped searching (e.g. after ``BonjourNetworkBrowsing/stop()``).
    func bonjourBrowserDidStopSearch()

    /// The browser failed to start searching.
    ///
    /// - Parameter error: The underlying error (typically a ``BonjourDiscoveryError/searchFailed(_:)``).
    func bonjourBrowser(didNotSearch error: any Error)
}

// MARK: - BonjourServiceResolving

/// Abstraction over ``NetService`` resolution for testability.
///
/// The production implementation ``SystemBonjourResolver`` drives a real
/// ``NetService`` on the main RunLoop using async/await. In tests, inject
/// a stub that returns a ``BonjourResolvedService`` synchronously.
public protocol BonjourServiceResolving: Sendable {

    /// Resolve a discovered service descriptor to a concrete host, port, and TXT record.
    ///
    /// - Parameters:
    ///   - service: Descriptor from a ``BonjourNetworkBrowsingDelegate`` callback.
    ///   - timeout: Maximum seconds to wait for resolution.
    /// - Returns: The fully resolved service.
    /// - Throws: ``BonjourDiscoveryError/resolutionTimeout`` if the service
    ///   does not resolve within `timeout` seconds.
    func resolve(_ service: BonjourServiceDescriptor, timeout: TimeInterval) async throws -> BonjourResolvedService
}

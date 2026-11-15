import Foundation
import os

// MARK: - MDNSBrowser

/// Generic mDNS/Bonjour browser that discovers services of any service type
/// on the local network.
///
/// ``MDNSBrowser`` is a direct generalization of `BrainyTubeKit`'s
/// `BonjourBrowser` (extracted 2026-06-21). The only behavioral change is
/// that the service type is now a constructor parameter instead of a hardcoded
/// `_brainytube._tcp` constant — making it reusable for any Bonjour service.
///
/// ## Typical usage
///
/// ```swift
/// let browser = MDNSBrowser(serviceType: "_shi-nats._tcp.")
/// let services = try await browser.discover(timeout: 10)
/// for svc in services {
///     print("\(svc.name) @ \(svc.hostName):\(svc.port)")
/// }
/// ```
///
/// ## Testability
///
/// The ``BonjourNetworkBrowsing`` and ``BonjourServiceResolving`` dependencies
/// can be replaced with fakes in unit tests — no real network required.
///
/// ```swift
/// let mock = MockBonjourBrowser()
/// let browser = MDNSBrowser(serviceType: "_test._tcp.", networkBrowser: mock)
/// mock.simulateFound(BonjourServiceDescriptor(name: "Foo", type: "_test._tcp.", domain: "local."))
/// let results = try await browser.discover(timeout: 1)
/// ```
///
/// ## Service discovery algorithm
///
/// 1. Start ``NetServiceBrowser`` (via the ``BonjourNetworkBrowsing`` seam).
/// 2. For each found descriptor, launch a resolution task in background.
/// 3. Poll every 500 ms. On first resolved result: wait 2 s more for stragglers.
/// 4. Stop the browser and return all resolved services.
///
/// - SeeAlso: ``BonjourNetworkBrowsing``, ``BonjourServiceResolving``,
///   ``SystemBonjourBrowser``, ``SystemBonjourResolver``
public final class MDNSBrowser: Sendable {

    // MARK: - Public constants

    /// The default search domain for mDNS / Bonjour (`"local."`).
    public static let defaultSearchDomain = "local."

    // MARK: - Init

    /// Create a browser for the given Bonjour service type.
    ///
    /// - Parameters:
    ///   - serviceType: Full Bonjour service type string **with** trailing dot
    ///     (e.g. `"_shi-nats._tcp."`, `"_http._tcp."`).
    ///   - searchDomain: mDNS domain to search in. Defaults to `"local."`.
    ///   - networkBrowser: Abstraction over ``NetServiceBrowser``.
    ///     Defaults to ``SystemBonjourBrowser``.
    ///   - resolver: Abstraction over ``NetService`` resolution.
    ///     Defaults to ``SystemBonjourResolver``.
    public init(
        serviceType: String,
        searchDomain: String = MDNSBrowser.defaultSearchDomain,
        networkBrowser: any BonjourNetworkBrowsing = SystemBonjourBrowser(),
        resolver: any BonjourServiceResolving = SystemBonjourResolver()
    ) {
        self.serviceType = serviceType
        self.searchDomain = searchDomain
        self.networkBrowser = networkBrowser
        self.serviceResolver = resolver
    }

    // MARK: - Discovery

    /// Discover services on the local network and return all that resolve
    /// within `timeout`.
    ///
    /// The method returns early (with a 2-second grace window for stragglers)
    /// once at least one service is resolved, rather than waiting the full
    /// `timeout` every time.
    ///
    /// - Parameter timeout: Maximum duration (seconds) to wait for services.
    ///   Defaults to `10.0`.
    /// - Returns: Array of resolved services (order not guaranteed).
    /// - Throws: Propagates task cancellation; discovery errors are silently
    ///   swallowed per-service (a resolution failure never aborts the whole
    ///   scan).
    public func discover(timeout: TimeInterval = 10.0) async throws -> [BonjourResolvedService] {
        let delegate = BrowserDelegateAdapter(browser: self)
        networkBrowser.browsingDelegate = delegate
        state.withLock { $0 = BrowserState() }

        // NetServiceBrowser MUST be scheduled on a RunLoop.
        await MainActor.run {
            networkBrowser.searchForServices(ofType: serviceType, inDomain: searchDomain)
        }

        let deadline = Date().addingTimeInterval(timeout)
        var foundFirst = false

        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(500))

            let count = state.withLock { $0.resolvedServers.count }
            if count > 0 {
                if !foundFirst {
                    // Wait an extra 2 s for stragglers before returning.
                    foundFirst = true
                    try? await Task.sleep(for: .seconds(2))
                }
                break
            }
        }

        await MainActor.run {
            networkBrowser.stop()
        }

        return state.withLock { Array($0.resolvedServers.values) }
    }

    /// Stop any ongoing discovery immediately.
    ///
    /// Safe to call from any context; idempotent.
    public func stopDiscovery() {
        networkBrowser.stop()
    }

    // MARK: - Private

    private let serviceType: String
    private let searchDomain: String
    private let networkBrowser: any BonjourNetworkBrowsing
    private let serviceResolver: any BonjourServiceResolving
    private let state = OSAllocatedUnfairLock(initialState: BrowserState())

    fileprivate func handleServiceFound(_ service: BonjourServiceDescriptor) {
        state.withLock { $0.pendingServices.append(service) }

        Task {
            do {
                let resolved = try await serviceResolver.resolve(service, timeout: 5.0)
                state.withLock {
                    // Only keep the result if the service wasn't removed during resolution.
                    if $0.pendingServices.contains(service) {
                        $0.resolvedServers[resolved.name] = resolved
                    }
                }
            } catch {
                // Resolution failure is non-fatal — skip this service.
            }
        }
    }

    fileprivate func handleServiceRemoved(_ service: BonjourServiceDescriptor) {
        state.withLock {
            $0.pendingServices.removeAll { $0 == service }
            $0.resolvedServers.removeValue(forKey: service.name)
        }
    }
}

// MARK: - BrowserState

/// Thread-safe state bag for ``MDNSBrowser``.
private struct BrowserState: Sendable {
    var pendingServices: [BonjourServiceDescriptor] = []
    var resolvedServers: [String: BonjourResolvedService] = [:]
}

// MARK: - BrowserDelegateAdapter

/// Bridges ``BonjourNetworkBrowsingDelegate`` callbacks to ``MDNSBrowser``
/// internal methods.
private final class BrowserDelegateAdapter: BonjourNetworkBrowsingDelegate, @unchecked Sendable {

    private let browser: MDNSBrowser

    init(browser: MDNSBrowser) {
        self.browser = browser
    }

    func bonjourBrowser(didFind service: BonjourServiceDescriptor, moreComing: Bool) {
        browser.handleServiceFound(service)
    }

    func bonjourBrowser(didRemove service: BonjourServiceDescriptor, moreComing: Bool) {
        browser.handleServiceRemoved(service)
    }

    func bonjourBrowserDidStopSearch() {}

    func bonjourBrowser(didNotSearch error: any Error) {}
}

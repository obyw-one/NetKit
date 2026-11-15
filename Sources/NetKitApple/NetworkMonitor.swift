#if canImport(Network)
//
//  NetworkMonitor.swift
//  NetKit
//

import CoreKit
import Foundation
import Network

/// Monitors network reachability and interface type using `NWPathMonitor`.
///
/// Emits interface changes as an `AsyncStream<InterfaceType>` and exposes
/// a synchronous ``isConnected`` property for quick checks.
///
/// ```swift
/// let monitor = NetworkMonitor()
/// for await interface in await monitor.start() {
///     print("Now on: \(interface)")
/// }
/// ```
///
/// ## Deprecated: reachability is a CoreKit capability (spec c8fa126c W3)
///
/// Reachability is not a NetKit concern — it is a platform capability, and
/// CoreKit declares it once as `ReachabilityProviding` with an `NWPathMonitor`
/// implementation on Apple and a `getifaddrs(3)` one elsewhere, both registered
/// by `CoreKitPlatformAssembly`. This actor is the Apple-only half of that, in
/// the wrong layer: a Linux host could not reach it at all.
///
/// Measured 2026-11-15, `grep -rln 'NetworkMonitor'` over every workspace's
/// `Sources`: **zero consumers outside this package** (the other two hits are
/// the `fuzzy-swift` and `NetKit-2` copies of this same file). It is deprecated
/// here rather than deleted so the one release that moves callers does not also
/// break them, and it is removed in NetKit 4.0.0.
///
/// Replacement:
/// ```swift
/// let reach = container.require((any ReachabilityProviding).self)
/// await reach.start()
/// for await interface in reach.updates() { … }
/// ```
@available(
    *, deprecated,
    message: """
    Resolve CoreKit's `any ReachabilityProviding` instead (CoreKit 0.18.0, spec c8fa126c W3).     Reachability is a platform capability, so it is declared once in CoreKit with an     implementation per target; this actor exists only on Apple. Removed in NetKit 4.0.0.
    """
)
public actor NetworkMonitor {
    /// The active network interface type.
    ///
    /// Was a second declaration of the same five cases CoreKit already owned —
    /// an enum beside the contract is a second vocabulary, not a contract
    /// ([[an-enum-beside-the-protocol-is-a-second-vocabulary-not-a-contract-delete-it]]).
    /// It is now an alias, so a value crosses between NetKit and CoreKit without
    /// a mapping function that can drift. Source-compatible: the five case names
    /// are identical.
    public typealias InterfaceType = CoreKit.NetworkInterfaceType

    private let monitor: NWPathMonitor
    private var continuation: AsyncStream<InterfaceType>.Continuation?

    public private(set) var currentInterface: InterfaceType = .unknown
    public var isConnected: Bool { currentInterface != .unknown }

    /// Creates a new network monitor. Call ``start(queue:)`` to begin observing.
    public init() {
        self.monitor = NWPathMonitor()
    }

    deinit {
        monitor.cancel()
    }

    /// Starts monitoring and returns a stream of interface-type changes.
    /// - Parameter queue: The dispatch queue for path updates (defaults to utility QoS).
    public func start(queue: DispatchQueue = .global(qos: .utility)) -> AsyncStream<InterfaceType> {
        let stream = AsyncStream<InterfaceType> { continuation in
            self.continuation = continuation
        }

        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            Task {
                let interfaceType = self.mapInterface(path)
                await self.update(interfaceType)
            }
        }
        monitor.start(queue: queue)
        return stream
    }

    /// Stops monitoring and finishes the interface stream.
    public func stop() {
        monitor.cancel()
        continuation?.finish()
        continuation = nil
    }

    private func update(_ type: InterfaceType) {
        currentInterface = type
        continuation?.yield(type)
        // Feed the process-wide store CoreKit's cache layer reads, so a host
        // that still drives this monitor gets the same reachability answer as
        // one that resolved `ReachabilityProviding`. Without this line the two
        // disagree, which is the drift the deprecation exists to end.
        Task { await NetworkReachabilityStore.shared.update(type) }
    }

    nonisolated private func mapInterface(_ path: NWPath) -> InterfaceType {
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.cellular) { return .cellular }
        if path.usesInterfaceType(.wiredEthernet) { return .ethernet }
        if path.usesInterfaceType(.loopback) { return .localhost }
        return .unknown
    }
}
#endif

#if canImport(Network)
//
//  NetworkMonitor.swift
//  NetKit
//

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
public actor NetworkMonitor {
    /// The active network interface type.
    public enum InterfaceType: Sendable, Equatable {
        case unknown
        case wifi
        case cellular
        case ethernet
        case localhost
    }

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

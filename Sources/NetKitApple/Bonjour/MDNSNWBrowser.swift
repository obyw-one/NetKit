#if canImport(Network) && (os(iOS) || os(tvOS) || os(macOS))
import Foundation
import Network
import Observation
import os

// MARK: - MDNSNWBrowser

/// Generic mDNS/Bonjour browser backed by ``NWBrowser`` (Network.framework).
///
/// ``MDNSNWBrowser`` is a direct generalization of `BrainyTubeKit`'s
/// `PushTargetBrowser` (extracted 2026-06-21). Instead of materializing
/// app-layer `PushTarget` structs, it exposes the raw ``NWBrowser/Result``
/// set for consumers to project into their own domain types.
///
/// ## Platform availability
///
/// ``NWBrowser`` is Apple-only (iOS 13+, macOS 10.15+, tvOS 13+). This class
/// is conditionally compiled under `#if canImport(Network)`. On Linux, use
/// ``MDNSBrowser`` (``NetServiceBrowser``-based) instead.
///
/// ## Typical usage
///
/// ```swift
/// @State private var nwBrowser = MDNSNWBrowser(serviceType: "_shi-nats._tcp")
///
/// .onAppear { nwBrowser.start() }
/// .onDisappear { nwBrowser.stop() }
///
/// // In your view body:
/// ForEach(nwBrowser.endpoints, id: \.endpoint) { result in
///     Text("\(result.endpoint)")
/// }
/// ```
///
/// ## Peer-to-peer
///
/// ``NWParameters/includePeerToPeer`` is set to `true` so that
/// Bonjour records from peer devices (iPhone-to-Apple-TV, etc.) are
/// visible without extra entitlements on LAN.
///
/// - SeeAlso: ``MDNSBrowser`` for the ``NetServiceBrowser``-based alternative
///   that works on both Apple and Linux.
@Observable
@MainActor
public final class MDNSNWBrowser {

    // MARK: - Observable surface

    /// Current set of discovered endpoints.
    ///
    /// Updated on the main actor whenever ``NWBrowser`` signals a change.
    /// Each ``NWBrowser/Result`` contains the endpoint, metadata (including
    /// TXT record), and interface flags.
    public private(set) var endpoints: [NWBrowser.Result] = []

    /// `true` while the underlying ``NWBrowser`` is active.
    public private(set) var isSearching: Bool = false

    // MARK: - Init

    /// Create a browser for the given Bonjour service type.
    ///
    /// - Parameters:
    ///   - serviceType: Bonjour service type **without** trailing dot
    ///     (e.g. `"_shi-nats._tcp"`, `"_http._tcp"`).
    ///     ``NWBrowser.Descriptor.bonjour(type:domain:)`` does not use
    ///     trailing dots; they are stripped automatically.
    public init(serviceType: String) {
        // NWBrowser expects no trailing dot; strip if caller included one.
        self.serviceType = serviceType.hasSuffix(".") ? String(serviceType.dropLast()) : serviceType
        self.logger = Logger(subsystem: "com.fj-studios.netkit", category: "MDNSNWBrowser")
    }

    // MARK: - Lifecycle

    /// Start browsing. Idempotent — safe to call if already started.
    public func start() {
        guard nwBrowser == nil else { return }

        let descriptor = NWBrowser.Descriptor.bonjour(type: serviceType, domain: nil)
        let params = NWParameters()
        params.includePeerToPeer = true

        let b = NWBrowser(for: descriptor, using: params)

        b.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { @MainActor in
                switch state {
                case .ready:
                    self.isSearching = true
                case .failed(let error):
                    self.isSearching = false
                    self.logger.error("[MDNSNWBrowser] browser failed: \(error, privacy: .public)")
                case .cancelled:
                    self.isSearching = false
                default:
                    break
                }
            }
        }

        b.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            let snapshot = results
            Task { @MainActor in
                self.endpoints = Array(snapshot).sorted {
                    $0.endpoint.debugDescription < $1.endpoint.debugDescription
                }
            }
        }

        nwBrowser = b
        b.start(queue: .main)
        isSearching = true

        logger.log("[MDNSNWBrowser] start serviceType=\(self.serviceType, privacy: .public)")
    }

    /// Stop browsing and clear the endpoint list.
    public func stop() {
        nwBrowser?.cancel()
        nwBrowser = nil
        endpoints = []
        isSearching = false

        logger.log("[MDNSNWBrowser] stop serviceType=\(self.serviceType, privacy: .public)")
    }

    // MARK: - Private

    private let serviceType: String
    private let logger: Logger
    private var nwBrowser: NWBrowser?
}
#endif

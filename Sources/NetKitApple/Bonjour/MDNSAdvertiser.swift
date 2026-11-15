import Foundation
import os

// MARK: - MDNSAdvertiser

/// Generic mDNS/Bonjour advertiser that publishes a service of any type
/// under a caller-specified name and port.
///
/// ``MDNSAdvertiser`` is a direct generalization of `BrainyTubeKit`'s
/// `BonjourReceiverAdvertiser` (extracted 2026-06-21). BrainyTube-specific
/// concerns (`capabilities`, `platform` TXT keys, `_brainytube-receiver._tcp`)
/// are replaced with a caller-supplied `txtRecord` dictionary.
///
/// ## Typical usage
///
/// ```swift
/// let advertiser = MDNSAdvertiser(
///     serviceType: "_shi-nats._tcp",
///     name: "My NATS Broker",
///     port: 4222,
///     txtRecord: ["version": "1", "node": "primary"]
/// )
/// advertiser.start()
/// // …later…
/// advertiser.stop()
/// ```
///
/// ## Architecture notes
///
/// Uses ``NetService`` (not ``NWListener``) so the advertiser is decoupled
/// from the listener that actually owns the port. The listener can be started
/// independently; the advertiser is handed the bound port after the fact.
///
/// ``start()`` is idempotent — calling it more than once is a no-op until
/// ``stop()`` is called. The ``isAdvertising`` flag is set *optimistically*
/// on ``start()`` and corrected to `false` if ``NetService`` reports a publish
/// failure via its delegate.
@MainActor
public final class MDNSAdvertiser {

    // MARK: - Observable state

    /// `true` while the underlying ``NetService`` is published.
    public private(set) var isAdvertising: Bool = false

    // MARK: - Init

    /// Create an advertiser.
    ///
    /// - Parameters:
    ///   - serviceType: Bonjour service type **without** trailing dot
    ///     (e.g. `"_shi-nats._tcp"`). The domain `"local."` is always used.
    ///   - name: Bonjour instance name shown in browsers and logs.
    ///   - port: Port the service is listening on. Must be a concrete port
    ///     (not `0`) — the advertiser does not own the listener.
    ///   - txtRecord: Key-value pairs to publish in the TXT record.
    public init(
        serviceType: String,
        name: String,
        port: UInt16,
        txtRecord: [String: String] = [:]
    ) {
        self.serviceType = serviceType
        self.name = name
        self.port = port
        self.txtRecord = txtRecord
        self.logger = Logger(subsystem: "com.fj-studios.netkit", category: "MDNSAdvertiser")
    }

    // MARK: - Lifecycle

    /// Start publishing. Idempotent — calling twice is a no-op.
    public func start() {
        guard !isAdvertising else { return }

        let service = NetService(
            domain: "local.",
            type: serviceType,
            name: name,
            port: Int32(port)
        )
        let publishDelegate = PublishDelegate(logger: logger) { [weak self] published in
            guard let self else { return }
            self.isAdvertising = published
        }
        service.delegate = publishDelegate
        service.setTXTRecord(BonjourTXTRecord.encode(txtRecord))
        service.schedule(in: .main, forMode: .common)
        service.publish()

        self.netService = service
        self.netServiceDelegate = publishDelegate
        // Set optimistically; PublishDelegate corrects to false on didNotPublish.
        isAdvertising = true

        logger.log(
            """
            [MDNSAdvertiser] publish name=\(self.name, privacy: .public) \
            port=\(self.port, privacy: .public) \
            type=\(self.serviceType, privacy: .public)
            """
        )
    }

    /// Stop publishing. Safe to call when not advertising.
    public func stop() {
        netService?.stop()
        netService?.remove(from: .main, forMode: .common)
        netService = nil
        netServiceDelegate = nil
        isAdvertising = false

        logger.log("[MDNSAdvertiser] stopped name=\(self.name, privacy: .public)")
    }

    // MARK: - Private

    private let serviceType: String
    private let name: String
    private let port: UInt16
    private let txtRecord: [String: String]
    private let logger: Logger

    private var netService: NetService?
    private var netServiceDelegate: PublishDelegate?
}

// MARK: - PublishDelegate

private final class PublishDelegate: NSObject, NetServiceDelegate, @unchecked Sendable {

    private let logger: Logger
    private let onStateChange: @MainActor (Bool) -> Void

    init(logger: Logger, onStateChange: @escaping @MainActor (Bool) -> Void) {
        self.logger = logger
        self.onStateChange = onStateChange
    }

    func netServiceDidPublish(_ sender: NetService) {
        logger.log("[MDNSAdvertiser] did publish \(sender.name, privacy: .public)")
        Task { @MainActor in onStateChange(true) }
    }

    func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        let code = errorDict[NetService.errorCode]?.intValue ?? -1
        logger.error("[MDNSAdvertiser] publish failed code=\(code, privacy: .public) name=\(sender.name, privacy: .public)")
        Task { @MainActor in onStateChange(false) }
    }
}

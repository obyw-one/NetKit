import Foundation

// MARK: - SystemBonjourBrowser

/// Production adapter wrapping ``NetServiceBrowser``.
///
/// Schedules the underlying browser on the main ``RunLoop`` so that delegate
/// callbacks fire reliably. The ``SystemBonjourBrowser/browsingDelegate``
/// property must be set before calling ``searchForServices(ofType:inDomain:)``.
///
/// This class conforms to ``BonjourNetworkBrowsing`` and is the default
/// dependency injected by ``MDNSBrowser``.
public final class SystemBonjourBrowser: NSObject, BonjourNetworkBrowsing, NetServiceBrowserDelegate, @unchecked Sendable {

    // MARK: - BonjourNetworkBrowsing

    public weak var browsingDelegate: (any BonjourNetworkBrowsingDelegate)?

    public func searchForServices(ofType type: String, inDomain domain: String) {
        browser.searchForServices(ofType: type, inDomain: domain)
    }

    public func stop() {
        browser.stop()
    }

    // MARK: - Init

    override public init() {
        super.init()
        browser.delegate = self
        // Schedule on the main RunLoop so delegate callbacks fire even when
        // the calling Task has no RunLoop of its own.
        browser.schedule(in: .main, forMode: .common)
    }

    // MARK: - Private

    private let browser = NetServiceBrowser()

    // MARK: - NetServiceBrowserDelegate

    public func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didFind service: NetService,
        moreComing: Bool
    ) {
        let descriptor = BonjourServiceDescriptor(
            name: service.name,
            type: service.type,
            domain: service.domain
        )
        browsingDelegate?.bonjourBrowser(didFind: descriptor, moreComing: moreComing)
    }

    public func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didRemove service: NetService,
        moreComing: Bool
    ) {
        let descriptor = BonjourServiceDescriptor(
            name: service.name,
            type: service.type,
            domain: service.domain
        )
        browsingDelegate?.bonjourBrowser(didRemove: descriptor, moreComing: moreComing)
    }

    public func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        browsingDelegate?.bonjourBrowserDidStopSearch()
    }

    public func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didNotSearch errorDict: [String: NSNumber]
    ) {
        let code = errorDict[NetService.errorCode]?.intValue ?? -1
        browsingDelegate?.bonjourBrowser(
            didNotSearch: BonjourDiscoveryError.searchFailed("NetServiceBrowser error code: \(code)")
        )
    }
}

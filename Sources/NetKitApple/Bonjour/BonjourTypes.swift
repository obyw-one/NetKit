import Foundation

// MARK: - BonjourServiceDescriptor

/// Lightweight descriptor for a discovered Bonjour service **before** resolution.
///
/// Produced by ``BonjourNetworkBrowsing`` delegate callbacks when a service
/// is found on the network. The descriptor does not include host or port
/// information — those are obtained by passing it to a ``BonjourServiceResolving``
/// implementation.
public struct BonjourServiceDescriptor: Sendable, Equatable {

    /// The Bonjour instance name (e.g. `"My NATS Broker"`).
    public let name: String

    /// The Bonjour service type (e.g. `"_shi-nats._tcp."`).
    public let type: String

    /// The search domain (typically `"local."`).
    public let domain: String

    public init(name: String, type: String, domain: String) {
        self.name = name
        self.type = type
        self.domain = domain
    }
}

// MARK: - BonjourResolvedService

/// A fully resolved Bonjour service including host, port, and parsed TXT record.
///
/// Produced by ``BonjourServiceResolving/resolve(_:timeout:)`` after a
/// ``BonjourServiceDescriptor`` is resolved to a concrete address.
public struct BonjourResolvedService: Sendable, Equatable {

    /// The Bonjour instance name — matches ``BonjourServiceDescriptor/name``.
    public let name: String

    /// Resolved hostname (e.g. `"my-mac.local"` or an IP address string).
    public let hostName: String

    /// TCP/UDP port number on which the service is listening.
    public let port: Int

    /// Parsed TXT record key-value pairs.
    ///
    /// Keys and values are decoded from the raw length-prefixed TXT record
    /// using ``BonjourTXTRecord/parse(_:)``.
    public let txtRecord: [String: String]

    public init(
        name: String,
        hostName: String,
        port: Int,
        txtRecord: [String: String]
    ) {
        self.name = name
        self.hostName = hostName
        self.port = port
        self.txtRecord = txtRecord
    }

    /// Convenience: read the `"baseURL"` TXT key if present.
    ///
    /// Useful for services that advertise their HTTP root in TXT records
    /// (common pattern in BrainyTube and shikki service registrations).
    public var baseURL: String? { txtRecord["baseURL"] }
}

// MARK: - BonjourDiscoveryError

/// Errors that can be thrown during Bonjour discovery and resolution.
public enum BonjourDiscoveryError: Error, Sendable {

    /// The resolution attempt timed out before a host/port was obtained.
    case resolutionTimeout

    /// The underlying ``NetServiceBrowser`` reported a search failure.
    ///
    /// The associated value contains a human-readable description of the error
    /// (e.g. the ``NetService/errorCode`` returned by the delegate).
    case searchFailed(String)
}

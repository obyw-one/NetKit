//
//  PocketConfig.swift
//  NetworkKit
//
//  The injected configuration of a PocketBase client — the sibling of
//  `UmamiConfig`, with the same rule: NO default URL, NO environment read, NO
//  global. Every value is supplied by the caller and validated once, at
//  construction, so a misconfiguration is a NAMED error at boot rather than an
//  opaque HTTP failure on the first request.
//

import Foundation

/// Errors thrown while building a ``PocketConfig``.
///
/// A missing or unusable configuration never falls back to anything: there is
/// no built-in server to fall back TO. Each case names exactly what was wrong,
/// and none of them echoes the offending value (an endpoint string can carry
/// credentials).
public enum PocketConfigError: Error, Equatable, Sendable, CustomStringConvertible {
    /// No endpoint was supplied: `nil`, empty or whitespace-only.
    case missingEndpoint
    /// A value was supplied but it is not a URL.
    case malformedEndpoint
    /// The scheme is neither `https` nor (opted in) `http`.
    case unsupportedScheme(String?)
    /// The scheme is `http` and `allowInsecureHTTP` was not passed.
    case insecureHTTPNotAllowed
    /// The URL has no host.
    case emptyHost
    /// The URL carries a path, query or fragment. The endpoint is the server
    /// ROOT: `PocketEndPoint` appends `/api/...` itself, so `https://host/api`
    /// would silently address `/api/api/...` and fail on every call.
    case unexpectedComponents
    /// `authorization` was supplied but is empty or whitespace-only.
    case blankAuthorization

    public var description: String {
        switch self {
        case .missingEndpoint:
            return "PocketBase endpoint is missing: no URL was supplied."
        case .malformedEndpoint:
            return "PocketBase endpoint is not a valid URL."
        case .unsupportedScheme(let scheme):
            return
                "PocketBase endpoint scheme \(scheme ?? "nil") is not supported (expected https, or http with allowInsecureHTTP: true)."
        case .insecureHTTPNotAllowed:
            return "PocketBase endpoint scheme is http; pass allowInsecureHTTP: true to opt in."
        case .emptyHost:
            return "PocketBase endpoint host is empty."
        case .unexpectedComponents:
            return "PocketBase endpoint must be the server root (scheme, host, optional port): it has a path, query or fragment."
        case .blankAuthorization:
            return "PocketBase authorization is blank; pass nil for none."
        }
    }
}

/// Injected configuration for a PocketBase client.
///
/// Only the server ROOT travels here (scheme, host, optional port) plus an
/// optional static credential. Per-user tokens obtained from a login are NOT
/// configuration: they are passed to each call.
///
/// Deliberately not `Codable`, unlike ``UmamiConfig``: this type can hold a
/// credential, and a `Codable` config is one `JSONEncoder` away from a cache
/// envelope or a log line. It also redacts the credential from its
/// descriptions.
public struct PocketConfig: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {

    /// Validated URL scheme — always `https` or `http`.
    public let scheme: String
    /// Validated host — never empty.
    public let host: String
    /// Explicit port, when the endpoint named one.
    public let port: Int?
    /// Value sent verbatim as the `Authorization` header when a call carries no
    /// token of its own (for example a static API token). `nil` sends none.
    public let authorization: String?

    /// Build a validated configuration from a URL.
    ///
    /// - Parameters:
    ///   - endpoint: Base URL of the PocketBase server, root only
    ///               (e.g. `https://pocket.example.test` or `http://127.0.0.1:8090`).
    ///   - authorization: Optional value sent verbatim as `Authorization` when a
    ///                    call supplies no token. Defaults to `nil`.
    ///   - allowInsecureHTTP: When `true`, an `http://` endpoint is accepted
    ///                        (a local server). Defaults to `false`.
    /// - Throws: ``PocketConfigError``.
    public init(
        endpoint: URL,
        authorization: String? = nil,
        allowInsecureHTTP: Bool = false
    ) throws(PocketConfigError) {
        let scheme = endpoint.scheme?.lowercased()
        switch scheme {
        case "https":
            self.scheme = "https"
        case "http":
            guard allowInsecureHTTP else { throw .insecureHTTPNotAllowed }
            self.scheme = "http"
        default:
            throw .unsupportedScheme(scheme)
        }

        guard let host = endpoint.host, !host.isEmpty else { throw .emptyHost }
        self.host = host
        port = endpoint.port

        guard endpoint.path.isEmpty || endpoint.path == "/", endpoint.query == nil, endpoint.fragment == nil else {
            throw .unexpectedComponents
        }

        if let authorization, authorization.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw .blankAuthorization
        }
        self.authorization = authorization
    }

    /// Build a validated configuration from a string that may be absent — the
    /// shape a setting or an environment variable arrives in.
    ///
    /// `nil`, empty and whitespace-only are ``PocketConfigError/missingEndpoint``,
    /// never a default.
    public init(
        endpoint: String?,
        authorization: String? = nil,
        allowInsecureHTTP: Bool = false
    ) throws(PocketConfigError) {
        guard let raw = endpoint?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            throw .missingEndpoint
        }
        guard let url = URL(string: raw) else { throw .malformedEndpoint }
        try self.init(endpoint: url, authorization: authorization, allowInsecureHTTP: allowInsecureHTTP)
    }

    public var description: String {
        let origin = "\(scheme)://\(host)" + (port.map { ":\($0)" } ?? "")
        return "PocketConfig(\(origin), authorization: \(authorization == nil ? "none" : "<redacted>"))"
    }

    public var debugDescription: String { description }
}

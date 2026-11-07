//
//  PocketEndPoint.swift
//  NetworkKit
//
//  The PocketBase wire contract, beside `UmamiEndPoint`: ONE open enum that
//  describes every call a client makes to a PocketBase server. The
//  ``PocketConfig`` travels with each case, so the endpoint has no global state
//  — no `EnvConfig`, no singleton, no default host.
//
//  "Open" is the point: the collection is a parameter of the case, so the same
//  enum addresses any collection of any PocketBase server. Nothing about an
//  app's own collections, models or business rules belongs here.
//

import CoreKit
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum PocketEndPoint: EndPoint {

    // MARK: - Records

    /// `GET /api/collections/{collection}/records` — a page of records.
    case list(config: PocketConfig, collection: String, query: PocketQuery = PocketQuery(), token: String? = nil)

    /// `GET /api/collections/{collection}/records/{id}` — one record.
    case view(
        config: PocketConfig,
        collection: String,
        id: String,
        expand: String? = nil,
        fields: String? = nil,
        token: String? = nil
    )

    /// `POST /api/collections/{collection}/records` — create a record.
    /// On an auth collection this is also how a user registers.
    case create(config: PocketConfig, collection: String, payload: PocketPayload, token: String? = nil)

    /// `PATCH /api/collections/{collection}/records/{id}` — update a record.
    ///
    /// PATCH, not PUT: PocketBase registers no PUT route for records, and
    /// answers one with 404 (measured against a live server).
    case update(config: PocketConfig, collection: String, id: String, payload: PocketPayload, token: String? = nil)

    /// `DELETE /api/collections/{collection}/records/{id}` — answers 204.
    case delete(config: PocketConfig, collection: String, id: String, token: String? = nil)

    // MARK: - Authentication

    /// `POST /api/collections/{collection}/auth-with-password`.
    case authWithPassword(config: PocketConfig, collection: String, identity: String, password: String)

    /// `POST /api/collections/{collection}/auth-refresh` — trade a still-valid
    /// token for a fresh one.
    case authRefresh(config: PocketConfig, collection: String, token: String)

    /// `POST /api/collections/{collection}/request-password-reset` — answers 204.
    case requestPasswordReset(config: PocketConfig, collection: String, email: String)

    /// `POST /api/collections/{collection}/confirm-password-reset` — answers 204.
    case confirmPasswordReset(
        config: PocketConfig,
        collection: String,
        resetToken: String,
        password: String,
        passwordConfirm: String
    )

    // MARK: - Custom routes

    /// `GET /api/{path}` — a route the server's own hooks registered
    /// (for example `custom/some-route`). `path` is relative to `/api/`.
    case route(config: PocketConfig, path: String, query: [String: String] = [:], token: String? = nil)

    // MARK: - EndPoint

    public var scheme: String { config.scheme }

    public var host: String { config.host }

    public var port: Int? { config.port }

    public var apiPath: String { "/api/" }

    public var apiFilePath: String { "/api/files/" }

    /// The path below ``apiPath``, unencoded. ``urlRequest()`` validates and
    /// percent-encodes each segment itself.
    public var path: String { segments.joined(separator: "/") }

    public var method: RequestMethod {
        switch self {
        case .list, .view, .route: return .GET
        case .create, .authWithPassword, .authRefresh, .requestPasswordReset, .confirmPasswordReset: return .POST
        case .update: return .PATCH
        case .delete: return .DELETE
        }
    }

    public var header: [String: String]? {
        var header = ["Accept": "application/json"]
        if payload != nil { header["Content-Type"] = "application/json" }
        if let authorization { header["Authorization"] = authorization }
        return header
    }

    public var body: [String: Any]? { payload?.untypedObject }

    public var queryParams: [String: Any]? {
        let items = queryItems
        guard !items.isEmpty else { return nil }
        var params: [String: Any] = [:]
        for item in items { params[item.name] = item.value }
        return params
    }
}

// MARK: - Request building

public extension PocketEndPoint {

    /// The `URLRequest` for this call, or a ``PocketError/invalidRequest(reason:)``
    /// that says why none could be built.
    ///
    /// Unlike the shared `NetworkProtocol.createRequest(endPoint:)`, nothing
    /// here traps or is swallowed: a collection name that climbs out of
    /// `/api/collections/` (`..`, an empty segment), a token holding a control
    /// character, or a body JSON cannot represent are refused BEFORE a byte is
    /// sent. Path segments and query values are percent-encoded against the
    /// RFC 3986 unreserved set, so a filter containing `&`, `=` or `+` reaches
    /// the server intact.
    func urlRequest() throws(PocketError) -> URLRequest {
        let segments = segments
        for segment in segments where segment.isEmpty || segment == "." || segment == ".." {
            throw .invalidRequest(reason: "path segment '\(segment)' is empty or relative")
        }
        if let token = bearerToken, !Self.isHeaderSafe(token) {
            throw .invalidRequest(reason: "the token is empty or contains whitespace or a control character")
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        var encodedSegments: [String] = []
        for segment in segments {
            encodedSegments.append(try Self.percentEncode(segment))
        }
        components.percentEncodedPath = "/api/" + encodedSegments.joined(separator: "/")
        let items = queryItems
        if !items.isEmpty {
            var pairs: [String] = []
            for item in items {
                pairs.append(try Self.percentEncode(item.name) + "=" + Self.percentEncode(item.value))
            }
            components.percentEncodedQuery = pairs.joined(separator: "&")
        }
        guard let url = components.url else {
            throw .invalidRequest(reason: "the endpoint does not form a URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.allHTTPHeaderFields = header
        if let payload {
            request.httpBody = try payload.jsonData()
        }
        return request
    }

    /// `true` for the calls that establish or renew a session. A 400 from one
    /// of them is a rejected credential, not a malformed request.
    var isAuthenticationFlow: Bool {
        switch self {
        case .authWithPassword, .authRefresh: return true
        default: return false
        }
    }

    /// `"METHOD /path"` — what a failure reports, with no query and no values.
    var summary: String {
        "\(method.rawValue) /api/\(path)"
    }
}

// MARK: - Description (redacted)

extension PocketEndPoint: CustomStringConvertible, CustomDebugStringConvertible {
    /// `"METHOD /api/path"` only. The default enum description would print every
    /// associated value, passwords and tokens included.
    public var description: String { summary }
    public var debugDescription: String { summary }
}

// MARK: - Case anatomy

extension PocketEndPoint {

    var config: PocketConfig {
        switch self {
        case .list(let config, _, _, _),
             .view(let config, _, _, _, _, _),
             .create(let config, _, _, _),
             .update(let config, _, _, _, _),
             .delete(let config, _, _, _),
             .authWithPassword(let config, _, _, _),
             .authRefresh(let config, _, _),
             .requestPasswordReset(let config, _, _),
             .confirmPasswordReset(let config, _, _, _, _),
             .route(let config, _, _, _):
            return config
        }
    }

    /// The path below `/api/`, one entry per segment, before encoding.
    var segments: [String] {
        switch self {
        case .list(_, let collection, _, _), .create(_, let collection, _, _):
            return ["collections", collection, "records"]
        case .view(_, let collection, let id, _, _, _),
             .update(_, let collection, let id, _, _),
             .delete(_, let collection, let id, _):
            return ["collections", collection, "records", id]
        case .authWithPassword(_, let collection, _, _):
            return ["collections", collection, "auth-with-password"]
        case .authRefresh(_, let collection, _):
            return ["collections", collection, "auth-refresh"]
        case .requestPasswordReset(_, let collection, _):
            return ["collections", collection, "request-password-reset"]
        case .confirmPasswordReset(_, let collection, _, _, _):
            return ["collections", collection, "confirm-password-reset"]
        case .route(_, let path, _, _):
            return path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        }
    }

    /// The call's own token, or nil. A call without one falls back to the
    /// configured credential — see ``authorization``.
    var bearerToken: String? {
        switch self {
        case .list(_, _, _, let token),
             .view(_, _, _, _, _, let token),
             .create(_, _, _, let token),
             .update(_, _, _, _, let token),
             .delete(_, _, _, let token),
             .route(_, _, _, let token):
            return token
        case .authRefresh(_, _, let token):
            return token
        case .authWithPassword, .requestPasswordReset, .confirmPasswordReset:
            return nil
        }
    }

    /// The `Authorization` header value: the call's token as a bearer token,
    /// else the configured credential verbatim, else none.
    var authorization: String? {
        if let token = bearerToken { return "Bearer \(token)" }
        return config.authorization
    }

    var payload: PocketPayload? {
        switch self {
        case .create(_, _, let payload, _), .update(_, _, _, let payload, _):
            return payload
        case .authWithPassword(_, _, let identity, let password):
            return PocketPayload(fields: ["identity": .string(identity), "password": .string(password)])
        case .requestPasswordReset(_, _, let email):
            return PocketPayload(fields: ["email": .string(email)])
        case .confirmPasswordReset(_, _, let resetToken, let password, let passwordConfirm):
            return PocketPayload(fields: [
                "token": .string(resetToken),
                "password": .string(password),
                "passwordConfirm": .string(passwordConfirm),
            ])
        case .list, .view, .delete, .authRefresh, .route:
            return nil
        }
    }

    var queryItems: [(name: String, value: String)] {
        switch self {
        case .list(_, _, let query, _):
            return query.items
        case .view(_, _, _, let expand, let fields, _):
            var items: [(name: String, value: String)] = []
            if let expand { items.append(("expand", expand)) }
            if let fields { items.append(("fields", fields)) }
            return items
        case .route(_, _, let query, _):
            return query.sorted { $0.key < $1.key }.map { (name: $0.key, value: $0.value) }
        default:
            return []
        }
    }

    // MARK: Encoding helpers

    /// RFC 3986 unreserved characters. Everything else, `/ ? # & = + ( ) ' space`
    /// and every non-ASCII character included, is percent-encoded.
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    static func percentEncode(_ value: String) throws(PocketError) -> String {
        guard let encoded = value.addingPercentEncoding(withAllowedCharacters: unreserved) else {
            throw .invalidRequest(reason: "a path or query value cannot be percent-encoded")
        }
        return encoded
    }

    /// A header value may not carry whitespace or control characters (a token is
    /// a JWT: base64url and dots).
    static func isHeaderSafe(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { $0.value > 0x20 && $0.value < 0x7F }
    }
}

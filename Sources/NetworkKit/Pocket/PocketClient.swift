//
//  PocketClient.swift
//  NetworkKit
//
//  The generic PocketBase client: records (list, view, create, update, delete),
//  the auth flows (password login, refresh, password reset) and custom routes,
//  over an injected ``PocketConfig`` and ``PocketTransport``.
//
//  It follows `UmamiTrackUseCase`'s conventions — an injected config, an
//  injected seam, an `async` API, ONE typed error — and is the part that keeps
//  what the shared `NetworkProtocol` throws away: the server's own error body.
//

import CoreKit
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Protocol

/// What a consumer codes against. Conform a mock to it to test anything built
/// on PocketBase without a transport.
///
/// Every requirement is explicit about its token; ``PocketClient`` adds the
/// defaults. A call's `token` is the bearer token a login returned. When it is
/// `nil` the call falls back to ``PocketConfig/authorization``, and when that
/// is `nil` too the call is anonymous.
public protocol PocketClientProtocol: Sendable {
    /// A page of records.
    func list<Record: Decodable & Sendable>(
        collection: String,
        query: PocketQuery,
        token: String?
    ) async throws(PocketError) -> PocketListContainer<Record>

    /// One record.
    func view<Record: Decodable & Sendable>(
        collection: String,
        id: String,
        expand: String?,
        fields: String?,
        token: String?
    ) async throws(PocketError) -> Record

    /// Create a record; returns it as the server stored it.
    func create<Record: Decodable & Sendable>(
        collection: String,
        payload: PocketPayload,
        token: String?
    ) async throws(PocketError) -> Record

    /// Update a record (PATCH); returns it as the server stored it.
    func update<Record: Decodable & Sendable>(
        collection: String,
        id: String,
        payload: PocketPayload,
        token: String?
    ) async throws(PocketError) -> Record

    /// Delete a record.
    func delete(collection: String, id: String, token: String?) async throws(PocketError)

    /// Log in with an identity (username or email) and a password.
    func authWithPassword<Record: Decodable & Sendable>(
        collection: String,
        identity: String,
        password: String
    ) async throws(PocketError) -> PocketAuthResponse<Record>

    /// Trade a still-valid token for a fresh one.
    func authRefresh<Record: Decodable & Sendable>(
        collection: String,
        token: String
    ) async throws(PocketError) -> PocketAuthResponse<Record>

    /// Ask the server to email a password-reset link.
    func requestPasswordReset(collection: String, email: String) async throws(PocketError)

    /// Complete a password reset with the token from that email.
    func confirmPasswordReset(
        collection: String,
        resetToken: String,
        password: String,
        passwordConfirm: String
    ) async throws(PocketError)

    /// A custom route the server registered, relative to `/api/`.
    func route<Response: Decodable & Sendable>(
        _ path: String,
        query: [String: String],
        token: String?
    ) async throws(PocketError) -> Response
}

// MARK: - Implementation

/// ```swift
/// let config = try PocketConfig(endpoint: URL(string: "https://pocket.example.test")!)
/// let client = PocketClient(config: config)
///
/// let session: PocketAuthResponse<Account> = try await client.authWithPassword(
///     collection: "users", identity: "ada@example.test", password: password
/// )
/// let open: PocketListContainer<Task> = try await client.list(
///     collection: "tasks",
///     query: PocketQuery(perPage: 20, sort: "-created", filter: "done = false"),
///     token: session.token
/// )
/// ```
///
/// PocketBase dates decode through the fleet strategy
/// (`JSONDecoder.pocketbaseDateDecodingStrategy()`). That strategy rejects an
/// empty string, which is how PocketBase serialises a date field nobody set, so
/// a plain `Date?` property cannot read an unset date: decode optional dates
/// with ``Swift/KeyedDecodingContainer/decodePocketDateIfPresent(forKey:)``.
public struct PocketClient: PocketClientProtocol {
    private let config: PocketConfig
    private let transport: any PocketTransport

    /// - Parameters:
    ///   - config: The validated server root. No default: a client without a
    ///     configuration cannot exist.
    ///   - transport: Defaults to a `URLSession`; tests inject
    ///     ``MockPocketTransport``.
    public init(config: PocketConfig, transport: any PocketTransport = URLSessionPocketTransport()) {
        self.config = config
        self.transport = transport
    }

    // MARK: Records

    public func list<Record: Decodable & Sendable>(
        collection: String,
        query: PocketQuery = PocketQuery(),
        token: String? = nil
    ) async throws(PocketError) -> PocketListContainer<Record> {
        try await decoded(.list(config: config, collection: collection, query: query, token: token))
    }

    public func view<Record: Decodable & Sendable>(
        collection: String,
        id: String,
        expand: String? = nil,
        fields: String? = nil,
        token: String? = nil
    ) async throws(PocketError) -> Record {
        try await decoded(.view(
            config: config, collection: collection, id: id, expand: expand, fields: fields, token: token
        ))
    }

    public func create<Record: Decodable & Sendable>(
        collection: String,
        payload: PocketPayload,
        token: String? = nil
    ) async throws(PocketError) -> Record {
        try await decoded(.create(config: config, collection: collection, payload: payload, token: token))
    }

    /// Create a record from a `Codable` model.
    public func create<Record: Decodable & Sendable>(
        collection: String,
        record: some Encodable,
        token: String? = nil
    ) async throws(PocketError) -> Record {
        try await create(collection: collection, payload: PocketPayload(record), token: token)
    }

    public func update<Record: Decodable & Sendable>(
        collection: String,
        id: String,
        payload: PocketPayload,
        token: String? = nil
    ) async throws(PocketError) -> Record {
        try await decoded(.update(config: config, collection: collection, id: id, payload: payload, token: token))
    }

    /// Update a record from a `Codable` model. Every field of the model is sent;
    /// send a narrower model to patch fewer fields.
    public func update<Record: Decodable & Sendable>(
        collection: String,
        id: String,
        record: some Encodable,
        token: String? = nil
    ) async throws(PocketError) -> Record {
        try await update(collection: collection, id: id, payload: PocketPayload(record), token: token)
    }

    public func delete(collection: String, id: String, token: String? = nil) async throws(PocketError) {
        _ = try await send(.delete(config: config, collection: collection, id: id, token: token))
    }

    // MARK: Authentication

    public func authWithPassword<Record: Decodable & Sendable>(
        collection: String,
        identity: String,
        password: String
    ) async throws(PocketError) -> PocketAuthResponse<Record> {
        try await decoded(.authWithPassword(
            config: config, collection: collection, identity: identity, password: password
        ))
    }

    public func authRefresh<Record: Decodable & Sendable>(
        collection: String,
        token: String
    ) async throws(PocketError) -> PocketAuthResponse<Record> {
        try await decoded(.authRefresh(config: config, collection: collection, token: token))
    }

    public func requestPasswordReset(collection: String, email: String) async throws(PocketError) {
        _ = try await send(.requestPasswordReset(config: config, collection: collection, email: email))
    }

    public func confirmPasswordReset(
        collection: String,
        resetToken: String,
        password: String,
        passwordConfirm: String
    ) async throws(PocketError) {
        _ = try await send(.confirmPasswordReset(
            config: config,
            collection: collection,
            resetToken: resetToken,
            password: password,
            passwordConfirm: passwordConfirm
        ))
    }

    // MARK: Custom routes

    public func route<Response: Decodable & Sendable>(
        _ path: String,
        query: [String: String] = [:],
        token: String? = nil
    ) async throws(PocketError) -> Response {
        try await decoded(.route(config: config, path: path, query: query, token: token))
    }
}

// MARK: - Plumbing

private extension PocketClient {

    /// Send, then decode the 2xx body into `Response`.
    func decoded<Response: Decodable & Sendable>(_ endpoint: PocketEndPoint) async throws(PocketError) -> Response {
        let (data, status) = try await send(endpoint)
        guard !data.isEmpty else { throw .emptyResponse(status: status) }
        do {
            return try PocketCodec.decoder().decode(Response.self, from: data)
        } catch let error as DecodingError {
            throw .decoding(error, status: status)
        } catch {
            // A model's own `init(from:)` threw something that is not a
            // DecodingError. Keep it as the underlying error.
            throw .decoding(
                .dataCorrupted(DecodingError.Context(
                    codingPath: [],
                    debugDescription: "the model's decoder threw a non-decoding error",
                    underlyingError: error
                )),
                status: status
            )
        }
    }

    /// Build the request, send it, and return the 2xx answer. Anything else is
    /// classified into a ``PocketError`` that keeps the server's body.
    func send(_ endpoint: PocketEndPoint) async throws(PocketError) -> (data: Data, status: Int) {
        let request = try endpoint.urlRequest()

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch is CancellationError {
            throw .cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw .cancelled
        } catch {
            throw .transport(error)
        }

        guard let http = response as? HTTPURLResponse else { throw .nonHTTPResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.error(for: endpoint, status: http.statusCode, data: data)
        }
        return (data, http.statusCode)
    }

    static func error(for endpoint: PocketEndPoint, status: Int, data: Data) -> PocketError {
        // A body that is not PocketBase's error shape (a proxy's HTML page) is
        // represented by `body == nil`; the bytes stay in `rawBody`.
        let body: PocketErrorBody?
        do {
            body = try PocketCodec.decoder().decode(PocketErrorBody.self, from: data)
        } catch {
            body = nil
        }
        let failure = PocketFailure(endpoint: endpoint.summary, status: status, body: body, rawBody: data)
        let rejectedCredential = status == 401 || status == 403 || (status == 400 && endpoint.isAuthenticationFlow)
        return rejectedCredential ? .authentication(failure) : .http(failure)
    }
}

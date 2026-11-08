//
//  MockNetworkService.swift
//  NetworkKit
//
//  Created for testing convenience.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A mock implementation of `NetworkProtocol` that returns configurable responses.
///
/// Usage:
/// ```swift
/// let mock = MockNetworkService()
/// mock.resultData = try JSONEncoder().encode(myModel)
/// let result: MyModel = try await mock.sendRequest(endpoint: someEndpoint)
/// ```
///
/// `Sendable` without `@unchecked`: the configuration and the captured
/// requests live in one value behind a ``LockedState``, and every public
/// property is a computed accessor over it. The synchronous API tests already
/// use (`mock.resultData = …`, `mock.capturedRequests`) is unchanged.
public final class MockNetworkService: NetworkProtocol, Sendable {

    private struct State: Sendable {
        var resultData: Data?
        var resultError: NetworkError?
        var statusCode = 200
        var capturedRequests: [URLRequest] = []
    }

    private let state = LockedState(State())

    // MARK: - Configurable State

    /// The raw data to return from requests. Encode your expected model into this.
    public var resultData: Data? {
        get { state.withLock { $0.resultData } }
        set { state.withLock { $0.resultData = newValue } }
    }

    /// An optional error to throw instead of returning data.
    public var resultError: NetworkError? {
        get { state.withLock { $0.resultError } }
        set { state.withLock { $0.resultError = newValue } }
    }

    /// The HTTP status code the mock pretends to return (default 200).
    public var statusCode: Int {
        get { state.withLock { $0.statusCode } }
        set { state.withLock { $0.statusCode = newValue } }
    }

    /// Tracks every `URLRequest` created via `createRequest(endPoint:)`.
    public var capturedRequests: [URLRequest] {
        state.withLock { $0.capturedRequests }
    }

    public init() {}

    // MARK: - NetworkProtocol

    public func sendRequest<T: Decodable>(endpoint: EndPoint) async throws -> T {
        try response(for: endpoint)
    }

    public func sendRequest<T: Decodable>(endpoint: EndPoint, resultHandler: @escaping @Sendable (Result<T, NetworkError>) -> Void) {
        do {
            resultHandler(.success(try response(for: endpoint)))
        } catch let error as NetworkError {
            resultHandler(.failure(error))
        } catch {
            resultHandler(.failure(.unknown(error)))
        }
    }

    /// Capture the request, then answer synchronously with the configured error,
    /// status or data. Public so the `NetKitApple` Combine publisher can reuse the
    /// same answer without a second copy of the logic.
    public func response<T: Decodable>(for endpoint: EndPoint) throws -> T {
        let request = createRequest(endPoint: endpoint)
        let configuration = state.withLock { state -> State in
            state.capturedRequests.append(request)
            return state
        }

        if let error = configuration.resultError {
            throw error
        }
        guard 200..<400 ~= configuration.statusCode else {
            throw NetworkError.unexpectedStatusCode(configuration.statusCode)
        }
        guard let data = configuration.resultData else {
            throw NetworkError.invalidData
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch let error as DecodingError {
            throw NetworkError.jsonParsingFailed(error)
        } catch {
            throw NetworkError.unknown(error)
        }
    }
}

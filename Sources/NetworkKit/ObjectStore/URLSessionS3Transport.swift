//
//  URLSessionS3Transport.swift
//  NetworkKit
//
//  Moved from CoreKit (spec d3f8a1b2). CoreKit keeps the `S3Transport` protocol, the
//  SigV4 signer and the request/response types and ships no transport; the caller injects
//  this one.
//

import CoreKit
import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The `URLSession` transport for CoreKit's `S3ObjectStoreClient`.
///
/// Three steps, and only the middle one does I/O: build the `URLRequest`
/// (``urlRequest(for:)``), load it, read the answer (``response(data:response:operation:)``).
/// The two ends are pure functions that RETURN their value, so a test checks them
/// directly instead of intercepting the network and recording what went through it
/// (#20 review: the `URLProtocol` stub needed a lock-guarded `@unchecked Sendable`
/// recorder, which is the smell, not the fix).
public struct URLSessionS3Transport: S3Transport {

  /// Loads one request: `URLSession.data(for:)` in production.
  typealias Load = @Sendable (URLRequest) async throws -> (Data, URLResponse)

  private static let hostHeader = "host"
  private let load: Load

  public init(session: URLSession = .shared) {
    self.load = { try await session.data(for: $0) }
  }

  /// A transport over any loader — how a test supplies the answer without a socket.
  init(load: @escaping Load) {
    self.load = load
  }

  public func send(_ request: S3Request) async throws -> S3Response {
    let (data, response) = try await load(Self.urlRequest(for: request))
    return try Self.response(data: data, response: response, operation: request.method)
  }

  /// The `URLRequest` for a signed `S3Request`. The `Host` header is not copied:
  /// the URL loading system derives it from the URL, which is what was signed.
  static func urlRequest(for request: S3Request) -> URLRequest {
    var urlRequest = URLRequest(url: request.url)
    urlRequest.httpMethod = request.method
    for (name, value) in request.headers where name.lowercased() != hostHeader {
      urlRequest.setValue(value, forHTTPHeaderField: name)
    }
    if !request.body.isEmpty { urlRequest.httpBody = request.body }
    return urlRequest
  }

  /// The `S3Response` for what the loader returned: status, headers lower-cased,
  /// body. A non-HTTP answer is malformed for `operation`.
  static func response(data: Data, response: URLResponse, operation: String) throws -> S3Response {
    guard let http = response as? HTTPURLResponse else {
      throw S3ObjectStoreError.malformedResponse(operation: operation, detail: "the response is not HTTP")
    }
    var headers: [String: String] = [:]
    for (name, value) in http.allHeaderFields {
      if let name = name as? String, let value = value as? String { headers[name.lowercased()] = value }
    }
    return S3Response(status: http.statusCode, headers: headers, body: data)
  }
}

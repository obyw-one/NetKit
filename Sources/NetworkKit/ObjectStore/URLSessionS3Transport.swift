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
public struct URLSessionS3Transport: S3Transport {

  private static let hostHeader = "host"
  private let session: URLSession

  public init(session: URLSession = .shared) {
    self.session = session
  }

  public func send(_ request: S3Request) async throws -> S3Response {
    var urlRequest = URLRequest(url: request.url)
    urlRequest.httpMethod = request.method
    for (name, value) in request.headers where name.lowercased() != Self.hostHeader {
      // The URL loading system derives Host from the URL (which is what was signed).
      urlRequest.setValue(value, forHTTPHeaderField: name)
    }
    if !request.body.isEmpty { urlRequest.httpBody = request.body }
    let (data, response) = try await session.data(for: urlRequest)
    guard let http = response as? HTTPURLResponse else {
      throw S3ObjectStoreError.malformedResponse(operation: request.method, detail: "the response is not HTTP")
    }
    var headers: [String: String] = [:]
    for (name, value) in http.allHeaderFields {
      if let name = name as? String, let value = value as? String { headers[name.lowercased()] = value }
    }
    return S3Response(status: http.statusCode, headers: headers, body: data)
  }
}

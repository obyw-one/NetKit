//
//  PocketTransport.swift
//  NetworkKit
//
//  The one seam between a PocketBase client and the network.
//
//  `NetworkProtocol.sendRequest` cannot be that seam: it throws on a non-2xx
//  status BEFORE it hands anything back, so the body — where PocketBase says
//  what is wrong — is gone by the time a caller could read it. This protocol
//  returns the bytes and the response untouched and leaves the judgement to
//  ``PocketClient``.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends one `URLRequest` and returns the answer untouched.
public protocol PocketTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse)
}

/// The production transport: a `URLSession`.
public struct URLSessionPocketTransport: PocketTransport {
    private let session: URLSession

    /// - Parameter session: Defaults to `URLSession.shared`. Pass an ephemeral
    ///   session to keep cookies and caches out of an authenticated client.
    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

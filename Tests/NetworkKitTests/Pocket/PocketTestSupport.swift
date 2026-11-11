//
//  PocketTestSupport.swift
//  NetworkKitTests
//
//  Shared fixtures for the PocketBase suites. Every host here is a reserved
//  `.test` name: no real server, and no internal hostname, appears in this
//  repository.
//

import Foundation
import Testing
@testable import NetKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum PocketFixtures {
    static let root = "https://pocket.example.test"

    /// A fake JWT. It is a fixture, not a credential.
    static let token = "eyJhbGciOiJIUzI1NiJ9.eyJpZCI6InVzZXIxIn0.c2lnbmF0dXJl"

    static func config(authorization: String? = nil) throws -> PocketConfig {
        try PocketConfig(endpoint: URL(string: root)!, authorization: authorization)
    }
}

/// A user-defined record, the way any consuming app would declare one.
struct Note: Codable, Equatable, Sendable {
    let id: String
    let title: String
    let done: Bool
    let score: Int
    let created: Date?
}

/// What a consumer sends to create a note.
struct NewNote: Codable, Hashable, Sendable {
    let title: String
    let done: Bool
    let score: Int
}

/// An auth-collection record.
struct Account: Codable, Equatable, Sendable {
    let id: String
    let email: String
    let verified: Bool
}

extension PocketFixtures {
    static func noteJSON(id: String = "rec000000000001", title: String = "first", done: Bool = false, score: Int = 1) -> String {
        """
        {"id":"\(id)","collectionId":"pbc_1","collectionName":"notes","title":"\(title)","done":\(done),"score":\(score),\
        "created":"2024-04-04 13:47:54.692Z"}
        """
    }

    static func listJSON(_ items: [String], page: Int = 1, perPage: Int = 30, totalItems: Int? = nil, totalPages: Int = 1) -> String {
        """
        {"page":\(page),"perPage":\(perPage),"totalPages":\(totalPages),"totalItems":\(totalItems ?? items.count),\
        "items":[\(items.joined(separator: ","))]}
        """
    }

    static let accountJSON = #"{"id":"user00000000001","collectionName":"users","email":"ada@example.test","verified":false}"#

    static func authJSON(token: String = PocketFixtures.token) -> String {
        #"{"token":"\#(token)","record":\#(accountJSON)}"#
    }

    static let wrongPasswordJSON = #"{"data":{},"message":"Failed to authenticate.","status":400}"#

    static let validationJSON = """
    {"data":{"title":{"code":"validation_required","message":"Cannot be blank."}},\
    "message":"Failed to create record.","status":400}
    """

    static let notFoundJSON = #"{"data":{},"message":"The requested resource wasn't found.","status":404}"#
}

/// The error a typed-throwing call threw, or nil when it did not throw.
func thrownError<T>(_ operation: () async throws(PocketError) -> T) async -> PocketError? {
    do throws(PocketError) {
        _ = try await operation()
        return nil
    } catch {
        return error
    }
}

/// Decode a captured request body through the same typed model production uses.
func decodeBody<Body: Decodable>(_ type: Body.Type, of request: URLRequest) throws -> Body {
    let data = try #require(request.httpBody, "the request carried no body")
    return try JSONDecoder().decode(type, from: data)
}

/// UTF-8 text of some bytes, or a failed expectation.
func utf8Text(_ data: Data) throws -> String {
    try #require(String(bytes: data, encoding: .utf8), "the bytes are not UTF-8")
}

/// One query parameter of a captured request, percent-decoded.
func queryValue(_ name: String, in request: URLRequest) throws -> String? {
    let url = try #require(request.url)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    return components.queryItems?.first { $0.name == name }?.value
}

//
//  NetworkServiceTests.swift
//  NetworkKitTests
//

import Foundation
import Testing
@testable import NetKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite("NetworkService Tests")
struct NetworkServiceTests {

    @Test("NetworkService conforms to NetworkProtocol")
    func conformsToProtocol() {
        let service = NetworkService()
        let _: any NetworkProtocol = service
        // If this compiles, the conformance is verified.
    }

    @Test("NetworkError descriptions are correct")
    func networkErrorDescriptions() {
        let requestFailed = NetworkError.requestFailed(description: "timeout")
        #expect(requestFailed.description == "Request failed: timeout")

        let statusCode = NetworkError.unexpectedStatusCode(404)
        #expect(statusCode.description == "Invalid status code: 404")

        let invalidData = NetworkError.invalidData
        #expect(invalidData.description == "Invalid data")
    }

    @Test("NetworkError with headers")
    func networkErrorWithHeaders() {
        let error = NetworkError.unexpectedStatusCode(500, headers: "Content-Type: application/json")
        #expect(error.description == "Invalid status code: 500")
    }

    @Test("URLQueryItem init from dictionary with string values")
    func queryItemsFromStringDict() {
        let dict: [String: Any] = ["key": "value", "name": "test"]
        let items = [URLQueryItem](from: dict)
        #expect(items.count == 2)
        let names = items.map(\.name).sorted()
        #expect(names == ["key", "name"])
    }

    @Test("URLQueryItem init from dictionary with nested values")
    func queryItemsFromNestedDict() {
        let dict: [String: Any] = ["filter": ["status": "active", "role": "admin"]]
        let items = [URLQueryItem](from: dict)
        #expect(items.count == 2)
        let names = items.map(\.name).sorted()
        #expect(names.contains("filter[role]"))
        #expect(names.contains("filter[status]"))
    }
}

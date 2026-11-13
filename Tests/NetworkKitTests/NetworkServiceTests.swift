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

@Suite("NetworkService injectable decoder")
struct NetworkServiceDecoderTests {
    private struct Row: Decodable, Equatable { let firstName: String }

    @Test("a snake_case decoder is used for the response")
    func customDecoderIsUsed() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let service = NetworkService(decoder: decoder)
        let row: Row = try service.decodeResponse(Data(#"{"first_name":"Ada"}"#.utf8))
        #expect(row == Row(firstName: "Ada"))
    }

    @Test("a decoderFactory is used for the response")
    func factoryIsUsed() throws {
        let service = NetworkService(decoderFactory: {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return decoder
        })
        let row: Row = try service.decodeResponse(Data(#"{"first_name":"Ada"}"#.utf8))
        #expect(row == Row(firstName: "Ada"))
    }

    @Test("the default service is unchanged: snake_case keys do not map")
    func defaultUnchanged() {
        let service = NetworkService()
        #expect(service.injectedDecoder() == nil)
        #expect(throws: NetworkError.self) {
            let _: Row = try service.decodeResponse(Data(#"{"first_name":"Ada"}"#.utf8))
        }
        #expect(throws: Never.self) {
            let _: Row = try service.decodeResponse(Data(#"{"firstName":"Ada"}"#.utf8))
        }
    }

    @Test("a mock conformer keeps the nil default")
    func mockDefault() {
        #expect(MockNetworkService().injectedDecoder() == nil)
    }
}

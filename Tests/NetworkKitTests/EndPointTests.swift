//
//  EndPointTests.swift
//  NetworkKitTests
//

import Foundation
import Testing
@testable import NetKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Test EndPoint

struct TestEndPoint: EndPoint, @unchecked Sendable {
    var host: String = "api.example.com"
    var port: Int?
    var scheme: String = "https"
    var apiPath: String = "/api/v1"
    var apiFilePath: String = ""
    var path: String = "/users"
    var method: RequestMethod = .GET
    var header: [String: String]? = ["Authorization": "Bearer token123"]
    var body: [String: Any]?
    var queryParams: [String: Any]?
}

// MARK: - Tests

@Suite("EndPoint Tests")
struct EndPointTests {

    @Test("Default scheme is https")
    func defaultScheme() {
        struct MinimalEndPoint: EndPoint, @unchecked Sendable {
            var host: String = "example.com"
            var path: String = "/test"
            var method: RequestMethod = .GET
            var header: [String: String]?
            var body: [String: Any]?
            var queryParams: [String: Any]?
        }

        let endpoint = MinimalEndPoint()
        #expect(endpoint.scheme == "https")
        #expect(endpoint.port == nil)
        #expect(endpoint.apiPath.isEmpty)
        #expect(endpoint.apiFilePath.isEmpty)
    }

    @Test("RequestMethod raw values")
    func requestMethodRawValues() {
        #expect(RequestMethod.GET.rawValue == "GET")
        #expect(RequestMethod.POST.rawValue == "POST")
        #expect(RequestMethod.PUT.rawValue == "PUT")
        #expect(RequestMethod.DELETE.rawValue == "DELETE")
    }

    @Test("createRequest builds correct URL")
    func createRequestBuildsURL() {
        let endpoint = TestEndPoint()
        let service = NetworkService()
        let request = service.createRequest(endPoint: endpoint)

        #expect(request.url?.scheme == "https")
        #expect(request.url?.host == "api.example.com")
        #expect(request.url?.path == "/api/v1/users" || request.url?.path() == "/api/v1/users")
        #expect(request.httpMethod == "GET")
        #expect(request.allHTTPHeaderFields?["Authorization"] == "Bearer token123")
    }

    @Test("createRequest includes query parameters")
    func createRequestWithQueryParams() {
        var endpoint = TestEndPoint()
        endpoint.queryParams = ["page": "1", "limit": "20"]
        let service = NetworkService()
        let request = service.createRequest(endPoint: endpoint)

        let urlString = request.url?.absoluteString ?? ""
        #expect(urlString.contains("page=1"))
        #expect(urlString.contains("limit=20"))
    }

    @Test("createRequest includes body as JSON")
    func createRequestWithBody() {
        var endpoint = TestEndPoint()
        endpoint.method = .POST
        endpoint.body = ["name": "Test" as NSString]
        let service = NetworkService()
        let request = service.createRequest(endPoint: endpoint)

        #expect(request.httpMethod == "POST")
        #expect(request.httpBody != nil)
    }

    @Test("createRequest with custom port")
    func createRequestWithPort() {
        var endpoint = TestEndPoint()
        endpoint.port = 8090
        let service = NetworkService()
        let request = service.createRequest(endPoint: endpoint)

        #expect(request.url?.port == 8090)
    }
}

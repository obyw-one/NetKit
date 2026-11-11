//
//  EndPointTests.swift
//  NetworkKitTests
//

import CoreKit
import Foundation
import Testing
@testable import NetKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Test EndPoint

/// Body and query are held as `JSONValue` (Sendable) and handed to the protocol as the
/// untyped dictionaries it asks for, so the fixture needs no `@unchecked`.
struct TestEndPoint: EndPoint {
    var host: String = "api.example.com"
    var port: Int?
    var scheme: String = "https"
    var apiPath: String = "/api/v1"
    var apiFilePath: String = ""
    var path: String = "/users"
    var method: RequestMethod = .GET
    var header: [String: String]? = ["Authorization": "Bearer token123"]
    var bodyFields: [String: JSONValue]?
    var queryFields: [String: JSONValue]?

    var body: [String: Any]? { bodyFields?.mapValues(\.untyped) }
    var queryParams: [String: Any]? { queryFields?.mapValues(\.untyped) }
}

// MARK: - Tests

@Suite("EndPoint Tests")
struct EndPointTests {

    @Test("Default scheme is https")
    func defaultScheme() {
        struct MinimalEndPoint: EndPoint {
            var host: String = "example.com"
            var path: String = "/test"
            var method: RequestMethod = .GET
            var header: [String: String]?
            var body: [String: Any]? { nil }
            var queryParams: [String: Any]? { nil }
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
    func createRequestBuildsURL() throws {
        let endpoint = TestEndPoint()
        let service = NetworkService()
        let request = try service.createRequest(endPoint: endpoint)

        #expect(request.url?.scheme == "https")
        #expect(request.url?.host == "api.example.com")
        #expect(request.url?.path == "/api/v1/users" || request.url?.path() == "/api/v1/users")
        #expect(request.httpMethod == "GET")
        #expect(request.allHTTPHeaderFields?["Authorization"] == "Bearer token123")
    }

    @Test("createRequest includes query parameters")
    func createRequestWithQueryParams() throws {
        var endpoint = TestEndPoint()
        endpoint.queryFields = ["page": .string("1"), "limit": .string("20")]
        let service = NetworkService()
        let request = try service.createRequest(endPoint: endpoint)

        let urlString = request.url?.absoluteString ?? ""
        #expect(urlString.contains("page=1"))
        #expect(urlString.contains("limit=20"))
    }

    @Test("createRequest includes body as JSON")
    func createRequestWithBody() throws {
        var endpoint = TestEndPoint()
        endpoint.method = .POST
        endpoint.bodyFields = ["name": .string("Test")]
        let service = NetworkService()
        let request = try service.createRequest(endPoint: endpoint)

        #expect(request.httpMethod == "POST")
        #expect(request.httpBody != nil)
    }

    @Test("createRequest with custom port")
    func createRequestWithPort() throws {
        var endpoint = TestEndPoint()
        endpoint.port = 8090
        let service = NetworkService()
        let request = try service.createRequest(endPoint: endpoint)

        #expect(request.url?.port == 8090)
    }

    // MARK: createRequest throws instead of crashing or silently dropping the body

    /// A body JSON cannot represent. Computed, so the fixture holds no `Any`.
    private struct UnencodableBodyEndPoint: EndPoint {
        var host: String { "api.example.com" }
        var path: String { "/users" }
        var apiPath: String { "/api/v1" }
        var method: RequestMethod { .POST }
        var header: [String: String]? { nil }
        var body: [String: Any]? { ["ratio": Double.nan] }
        var queryParams: [String: Any]? { nil }
    }

    private struct DateBodyEndPoint: EndPoint {
        var host: String { "api.example.com" }
        var path: String { "/users" }
        var apiPath: String { "/api/v1" }
        var method: RequestMethod { .POST }
        var header: [String: String]? { nil }
        var body: [String: Any]? { ["when": Date(timeIntervalSince1970: 0)] }
        var queryParams: [String: Any]? { nil }
    }

    /// A host with a path that does not start with "/": no URL can be formed.
    private func invalidURLEndPoint() -> TestEndPoint {
        var endpoint = TestEndPoint()
        endpoint.apiPath = ""
        endpoint.path = "users"
        return endpoint
    }

    @Test("test_createRequest_anEndpointThatFormsNoURL_throwsInvalidURL_insteadOfCrashing")
    func test_createRequest_anEndpointThatFormsNoURL_throwsInvalidURL_insteadOfCrashing() {
        do {
            _ = try NetworkService().createRequest(endPoint: invalidURLEndPoint())
            Issue.record("expected NetworkError.invalidURL")
        } catch {
            guard case .invalidURL(let description) = error else { Issue.record("expected .invalidURL, got \(error)"); return }
            #expect(description.contains("api.example.com"))
            #expect(description.contains("users"))
        }
    }

    @Test("test_createRequest_theInvalidURLDescription_neverCarriesTheQuery")
    func test_createRequest_theInvalidURLDescription_neverCarriesTheQuery() {
        var endpoint = invalidURLEndPoint()
        endpoint.queryFields = ["token": .string("s3cret-value")]
        do {
            _ = try NetworkService().createRequest(endPoint: endpoint)
            Issue.record("expected NetworkError.invalidURL")
        } catch {
            #expect(!error.description.contains("s3cret-value"))
        }
    }

    @Test("test_createRequest_aBodyJSONCannotRepresent_throws_insteadOfSendingWithoutIt", arguments: [0, 1])
    func test_createRequest_aBodyJSONCannotRepresent_throws_insteadOfSendingWithoutIt(_ flavour: Int) {
        let endpoint: any EndPoint = flavour == 0 ? UnencodableBodyEndPoint() : DateBodyEndPoint()
        do {
            _ = try NetworkService().createRequest(endPoint: endpoint)
            Issue.record("expected NetworkError.bodyEncodingFailed")
        } catch {
            guard case .bodyEncodingFailed(let cause) = error else { Issue.record("expected .bodyEncodingFailed, got \(error)"); return }
            #expect(cause is BodyNotJSONRepresentable)
            #expect(error.description.contains("could not be encoded"))
        }
    }

    @Test("test_sendRequest_async_propagatesTheBuildError_beforeAnythingIsSent")
    func test_sendRequest_async_propagatesTheBuildError_beforeAnythingIsSent() async {
        do {
            let _: [String: String] = try await NetworkService().sendRequest(endpoint: invalidURLEndPoint())
            Issue.record("expected a throw")
        } catch {
            guard case NetworkError.invalidURL = error else { Issue.record("expected .invalidURL, got \(error)"); return }
        }
    }

    @Test("test_sendRequest_closure_deliversTheBuildErrorAsAFailure")
    func test_sendRequest_closure_deliversTheBuildErrorAsAFailure() async {
        let failure: NetworkError? = await withCheckedContinuation { continuation in
            NetworkService().sendRequest(endpoint: UnencodableBodyEndPoint()) { (result: Result<[String: String], NetworkError>) in
                if case .failure(let error) = result { continuation.resume(returning: error) } else { continuation.resume(returning: nil) }
            }
        }
        guard case .bodyEncodingFailed? = failure else { Issue.record("expected .bodyEncodingFailed, got \(String(describing: failure))"); return }
    }

    @Test("test_mock_propagatesTheBuildError_andCapturesNothing")
    func test_mock_propagatesTheBuildError_andCapturesNothing() async {
        let mock = MockNetworkService()
        mock.resultData = Data("{}".utf8)
        do {
            let _: [String: String] = try await mock.sendRequest(endpoint: invalidURLEndPoint())
            Issue.record("expected a throw")
        } catch {
            guard case NetworkError.invalidURL = error else { Issue.record("expected .invalidURL, got \(error)"); return }
        }
        #expect(mock.capturedRequests.isEmpty)
    }

    @Test("test_createRequest_aValidRequest_isByteIdenticalToWhatItAlwaysWas")
    func test_createRequest_aValidRequest_isByteIdenticalToWhatItAlwaysWas() throws {
        var endpoint = TestEndPoint()
        endpoint.port = 8090
        endpoint.method = .POST
        endpoint.queryFields = ["limit": .string("20")]
        endpoint.bodyFields = ["a": .integer(1)]
        let request = try NetworkService().createRequest(endPoint: endpoint)

        #expect(request.url?.absoluteString == "https://api.example.com:8090/api/v1/users?limit=20")
        #expect(request.httpMethod == "POST")
        #expect(request.allHTTPHeaderFields == ["Authorization": "Bearer token123"])
        #expect(request.httpBody == Data(#"{"a":1}"#.utf8))
    }
}

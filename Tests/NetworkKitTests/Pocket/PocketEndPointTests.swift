//
//  PocketEndPointTests.swift
//  NetworkKitTests
//
//  The wire contract of every PocketEndPoint case: method, path, headers,
//  query and body, asserted on the endpoint AND on the URLRequest it builds.
//

import CoreKit
import Foundation
import Testing
@testable import NetKit

@Suite("PocketEndPoint — the PocketBase wire contract")
struct PocketEndPointTests {

    private let config: PocketConfig

    init() throws {
        config = try PocketFixtures.config()
    }

    private func queryItems(of request: URLRequest) throws -> [String: String] {
        let url = try #require(request.url)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    // MARK: Records

    @Test("test_list_default_isAGetWithNoQueryAndNoBody")
    func test_list_default_isAGetWithNoQueryAndNoBody() throws {
        let endpoint = PocketEndPoint.list(config: config, collection: "notes")
        #expect(endpoint.method == .GET)
        #expect(endpoint.scheme == "https")
        #expect(endpoint.host == "pocket.example.test")
        #expect(endpoint.port == nil)
        #expect(endpoint.apiPath == "/api/")
        #expect(endpoint.path == "collections/notes/records")
        #expect(endpoint.queryParams == nil)
        #expect(endpoint.body == nil)
        #expect(endpoint.header?["Accept"] == "application/json")
        #expect(endpoint.header?["Content-Type"] == nil)
        #expect(endpoint.header?["Authorization"] == nil)

        let request = try endpoint.urlRequest()
        #expect(request.url?.absoluteString == "https://pocket.example.test/api/collections/notes/records")
        #expect(request.httpMethod == "GET")
        #expect(request.httpBody == nil)
    }

    @Test("test_list_fullQuery_sendsEveryParameterInOrder")
    func test_list_fullQuery_sendsEveryParameterInOrder() throws {
        let query = PocketQuery(
            page: 2, perPage: 20, sort: "-created,title", filter: "done = false", expand: "author", fields: "id,title", skipTotal: true
        )
        let request = try PocketEndPoint.list(config: config, collection: "notes", query: query).urlRequest()
        let raw = try #require(request.url?.query)
        #expect(raw.hasPrefix("page=2&perPage=20&sort=-created%2Ctitle&filter=done%20%3D%20false&expand=author&fields=id%2Ctitle"))
        #expect(raw.hasSuffix("&skipTotal=true"))
        let items = try queryItems(of: request)
        #expect(items["sort"] == "-created,title")
        #expect(items["filter"] == "done = false")
        #expect(items["skipTotal"] == "true")
    }

    @Test("test_list_absentQueryFields_areNotSent_soServerDefaultsApply")
    func test_list_absentQueryFields_areNotSent_soServerDefaultsApply() throws {
        let request = try PocketEndPoint.list(config: config, collection: "notes", query: PocketQuery(perPage: 5)).urlRequest()
        #expect(request.url?.query == "perPage=5")
    }

    @Test("test_list_filterWithReservedCharacters_reachesTheServerIntact")
    func test_list_filterWithReservedCharacters_reachesTheServerIntact() throws {
        let filter = "(app_id='a b' && env='x+y=z&w')"
        let request = try PocketEndPoint.list(config: config, collection: "notes", query: PocketQuery(filter: filter)).urlRequest()
        let raw = try #require(request.url?.query)
        // No raw `&`, `=`, `+`, space or quote may survive in the VALUE, or the
        // server would split or mis-read the filter.
        let value = String(raw.dropFirst("filter=".count))
        for forbidden in ["&", "=", "+", " ", "'", "(", ")"] {
            #expect(!value.contains(forbidden), "\(forbidden) was not percent-encoded")
        }
        #expect(try queryItems(of: request)["filter"] == filter)
    }

    @Test("test_view_addressesOneRecord_withExpandAndFields")
    func test_view_addressesOneRecord_withExpandAndFields() throws {
        let endpoint = PocketEndPoint.view(config: config, collection: "notes", id: "abc123", expand: "author", fields: "id,title")
        #expect(endpoint.method == .GET)
        #expect(endpoint.path == "collections/notes/records/abc123")
        let request = try endpoint.urlRequest()
        #expect(request.url?.path == "/api/collections/notes/records/abc123")
        #expect(try queryItems(of: request) == ["expand": "author", "fields": "id,title"])
    }

    @Test("test_view_withoutExpandOrFields_hasNoQuery")
    func test_view_withoutExpandOrFields_hasNoQuery() throws {
        let request = try PocketEndPoint.view(config: config, collection: "notes", id: "abc123").urlRequest()
        #expect(request.url?.query == nil)
    }

    @Test("test_create_isAPostWithAJsonBody")
    func test_create_isAPostWithAJsonBody() throws {
        let payload = try PocketPayload(NewNote(title: "hello", done: false, score: 3))
        let endpoint = PocketEndPoint.create(config: config, collection: "notes", payload: payload)
        #expect(endpoint.method == .POST)
        #expect(endpoint.path == "collections/notes/records")
        #expect(endpoint.header?["Content-Type"] == "application/json")

        let request = try endpoint.urlRequest()
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(try decodeBody(NewNote.self, of: request) == NewNote(title: "hello", done: false, score: 3))
    }

    @Test("test_update_isAPatch_notAPut")
    func test_update_isAPatch_notAPut() throws {
        let payload = try PocketPayload(NewNote(title: "renamed", done: true, score: 4))
        let endpoint = PocketEndPoint.update(config: config, collection: "notes", id: "abc123", payload: payload)
        #expect(endpoint.method == .PATCH)
        let request = try endpoint.urlRequest()
        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.path == "/api/collections/notes/records/abc123")
    }

    @Test("test_delete_isADeleteWithNoBodyAndNoContentType")
    func test_delete_isADeleteWithNoBodyAndNoContentType() throws {
        let endpoint = PocketEndPoint.delete(config: config, collection: "notes", id: "abc123", token: PocketFixtures.token)
        #expect(endpoint.method == .DELETE)
        #expect(endpoint.body == nil)
        let request = try endpoint.urlRequest()
        #expect(request.httpBody == nil)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(PocketFixtures.token)")
    }

    // MARK: Authentication

    private struct LoginBody: Decodable, Equatable {
        let identity: String
        let password: String
    }

    private struct ResetRequestBody: Decodable, Equatable {
        let email: String
    }

    private struct ResetConfirmBody: Decodable, Equatable {
        let token: String
        let password: String
        let passwordConfirm: String
    }

    @Test("test_authWithPassword_postsIdentityAndPassword")
    func test_authWithPassword_postsIdentityAndPassword() throws {
        let endpoint = PocketEndPoint.authWithPassword(config: config, collection: "users", identity: "ada@example.test", password: "pw-123456")
        #expect(endpoint.method == .POST)
        #expect(endpoint.path == "collections/users/auth-with-password")
        #expect(endpoint.header?["Authorization"] == nil)
        let request = try endpoint.urlRequest()
        #expect(try decodeBody(LoginBody.self, of: request) == LoginBody(identity: "ada@example.test", password: "pw-123456"))
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test("test_authRefresh_postsWithTheBearerTokenAndNoBody")
    func test_authRefresh_postsWithTheBearerTokenAndNoBody() throws {
        let endpoint = PocketEndPoint.authRefresh(config: config, collection: "users", token: PocketFixtures.token)
        #expect(endpoint.method == .POST)
        #expect(endpoint.path == "collections/users/auth-refresh")
        let request = try endpoint.urlRequest()
        #expect(request.httpBody == nil)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(PocketFixtures.token)")
    }

    @Test("test_requestPasswordReset_postsTheEmail")
    func test_requestPasswordReset_postsTheEmail() throws {
        let endpoint = PocketEndPoint.requestPasswordReset(config: config, collection: "users", email: "ada@example.test")
        #expect(endpoint.path == "collections/users/request-password-reset")
        #expect(try decodeBody(ResetRequestBody.self, of: endpoint.urlRequest()) == ResetRequestBody(email: "ada@example.test"))
    }

    @Test("test_confirmPasswordReset_postsTokenAndBothPasswords")
    func test_confirmPasswordReset_postsTokenAndBothPasswords() throws {
        let endpoint = PocketEndPoint.confirmPasswordReset(
            config: config, collection: "users", resetToken: "reset-token", password: "new-password-1", passwordConfirm: "new-password-1"
        )
        #expect(endpoint.path == "collections/users/confirm-password-reset")
        let body = try decodeBody(ResetConfirmBody.self, of: endpoint.urlRequest())
        #expect(body == ResetConfirmBody(token: "reset-token", password: "new-password-1", passwordConfirm: "new-password-1"))
    }

    @Test("test_authFlows_areFlagged_soAFourHundredReadsAsARejectedCredential")
    func test_authFlows_areFlagged_soAFourHundredReadsAsARejectedCredential() {
        #expect(PocketEndPoint.authWithPassword(config: config, collection: "u", identity: "i", password: "p").isAuthenticationFlow)
        #expect(PocketEndPoint.authRefresh(config: config, collection: "u", token: PocketFixtures.token).isAuthenticationFlow)
        #expect(!PocketEndPoint.list(config: config, collection: "u").isAuthenticationFlow)
        #expect(!PocketEndPoint.requestPasswordReset(config: config, collection: "u", email: "e").isAuthenticationFlow)
    }

    // MARK: Custom routes

    @Test("test_route_isAGetBelowApi_withSortedQuery")
    func test_route_isAGetBelowApi_withSortedQuery() throws {
        let endpoint = PocketEndPoint.route(
            config: config, path: "custom/app-bootstrap", query: ["env": "prod", "app_id": "demo"], token: PocketFixtures.token
        )
        #expect(endpoint.method == .GET)
        let request = try endpoint.urlRequest()
        #expect(request.url?.absoluteString == "https://pocket.example.test/api/custom/app-bootstrap?app_id=demo&env=prod")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(PocketFixtures.token)")
    }

    // MARK: Credentials

    @Test("test_authorization_callToken_winsOverConfigCredential")
    func test_authorization_callToken_winsOverConfigCredential() throws {
        let configured = try PocketFixtures.config(authorization: "static-credential")
        let request = try PocketEndPoint.list(config: configured, collection: "notes", token: PocketFixtures.token).urlRequest()
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(PocketFixtures.token)")
    }

    @Test("test_authorization_withoutCallToken_usesTheConfigCredentialVerbatim")
    func test_authorization_withoutCallToken_usesTheConfigCredentialVerbatim() throws {
        let configured = try PocketFixtures.config(authorization: "static-credential")
        let request = try PocketEndPoint.list(config: configured, collection: "notes").urlRequest()
        #expect(request.value(forHTTPHeaderField: "Authorization") == "static-credential")
    }

    @Test("test_authorization_withNeither_isAnonymous")
    func test_authorization_withNeither_isAnonymous() throws {
        let request = try PocketEndPoint.list(config: config, collection: "notes").urlRequest()
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("test_port_isCarriedIntoTheUrl")
    func test_port_isCarriedIntoTheUrl() throws {
        let local = try PocketConfig(endpoint: URL(string: "http://127.0.0.1:8090")!, allowInsecureHTTP: true)
        let request = try PocketEndPoint.list(config: local, collection: "notes").urlRequest()
        #expect(request.url?.absoluteString == "http://127.0.0.1:8090/api/collections/notes/records")
    }

    // MARK: Refusals — nothing is sent for these

    @Test("test_urlRequest_relativeOrEmptySegments_areRefused", arguments: [
        ("..", "abc"), ("notes", ".."), ("", "abc"), ("notes", ""), (".", "abc"),
    ])
    func test_urlRequest_relativeOrEmptySegments_areRefused(_ collection: String, _ id: String) {
        let endpoint = PocketEndPoint.view(config: config, collection: collection, id: id)
        #expect(throws: PocketError.self) { try endpoint.urlRequest() }
    }

    @Test("test_urlRequest_slashInAName_staysOneEncodedSegment")
    func test_urlRequest_slashInAName_staysOneEncodedSegment() throws {
        let request = try PocketEndPoint.view(config: config, collection: "a/b", id: "x?y#z").urlRequest()
        #expect(request.url?.absoluteString == "https://pocket.example.test/api/collections/a%2Fb/records/x%3Fy%23z")
    }

    @Test("test_urlRequest_routeThatClimbsOrStartsWithSlash_isRefused", arguments: [
        "/custom/x", "custom//x", "custom/../admin", "..", "",
    ])
    func test_urlRequest_routeThatClimbsOrStartsWithSlash_isRefused(_ path: String) {
        #expect(throws: PocketError.self) {
            try PocketEndPoint.route(config: config, path: path).urlRequest()
        }
    }

    @Test("test_urlRequest_badTokens_areRefused", arguments: [
        "", "two words", "line\r\nbreak: injected", "tab\there", "naïve",
    ])
    func test_urlRequest_badTokens_areRefused(_ token: String) {
        #expect(throws: PocketError.self) {
            try PocketEndPoint.list(config: config, collection: "notes", token: token).urlRequest()
        }
    }

    @Test("test_urlRequest_unrepresentableBody_isRefusedBeforeAnythingIsSent")
    func test_urlRequest_unrepresentableBody_isRefusedBeforeAnythingIsSent() {
        let payload = PocketPayload(fields: ["ratio": .double(.nan)])
        let endpoint = PocketEndPoint.create(config: config, collection: "notes", payload: payload)
        #expect(throws: PocketError.self) { try endpoint.urlRequest() }
    }

    // MARK: Descriptions never carry a secret

    @Test("test_description_isMethodAndPathOnly_neverAPasswordOrToken")
    func test_description_isMethodAndPathOnly_neverAPasswordOrToken() {
        let login = PocketEndPoint.authWithPassword(config: config, collection: "users", identity: "ada@example.test", password: "pw-do-not-log")
        let refresh = PocketEndPoint.authRefresh(config: config, collection: "users", token: PocketFixtures.token)
        for endpoint in [login, refresh] {
            for text in [endpoint.description, endpoint.debugDescription, String(describing: endpoint), "\(endpoint)"] {
                #expect(!text.contains("pw-do-not-log"))
                #expect(!text.contains(PocketFixtures.token))
                #expect(!text.contains("ada@example.test"))
            }
        }
        #expect(login.description == "POST /api/collections/users/auth-with-password")
    }

    // MARK: The legacy EndPoint view

    @Test("test_endPointBody_isTheUntypedViewOfThePayload")
    func test_endPointBody_isTheUntypedViewOfThePayload() throws {
        let payload = try PocketPayload(NewNote(title: "hello", done: true, score: 1))
        let body = try #require(PocketEndPoint.create(config: config, collection: "notes", payload: payload).body)
        #expect(body["title"] as? String == "hello")
        #expect(body["score"] as? Int == 1)
        #expect((body["done"] as? NSNumber)?.boolValue == true)
        #expect(body.count == 3)
    }

    @Test("test_endPointQueryParams_mirrorTheQueryItems")
    func test_endPointQueryParams_mirrorTheQueryItems() throws {
        let endpoint = PocketEndPoint.list(config: config, collection: "notes", query: PocketQuery(perPage: 1, filter: "a = 1"))
        let params = try #require(endpoint.queryParams as? [String: String])
        #expect(params == ["perPage": "1", "filter": "a = 1"])
    }
}

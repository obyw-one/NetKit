//
//  PocketParityTests.swift
//  NetworkKitTests
//
//  Parity with the app-level PocketBase client this one graduated from.
//
//  The scenarios below are the ones a server-driven-configuration client
//  performs today: list with a filter, fetch the config records, call a custom
//  bootstrap route, mark a message read, log in, refresh, register. Each is
//  built twice — once the way the legacy `EndPoint` enums build it, through the
//  shared `NetworkProtocol.createRequest`, and once through `PocketEndPoint` —
//  and the two requests must agree. A consumer migrating to this client then
//  swaps constructors; it does not rewrite its calls.
//
//  Where they deliberately DISAGREE the test says so and says why.
//

import CoreKit
import Foundation
import Testing
@testable import NetKit

/// The legacy builder: an `EndPoint` described the old way, with the host
/// global replaced by a constant, built by the shared `createRequest`.
/// Bodies and queries are held as `JSONValue` (the fleet's Sendable JSON) and
/// handed to the protocol as the untyped dictionaries it asks for.
private struct LegacyEndPoint: EndPoint {
    let method: RequestMethod
    let path: String
    let header: [String: String]?
    let bodyFields: [String: JSONValue]?
    let queryFields: [String: JSONValue]?

    var host: String { "pocket.example.test" }
    var apiPath: String { "/api/" }
    var body: [String: Any]? { bodyFields?.mapValues(\.untyped) }
    var queryParams: [String: Any]? { queryFields?.mapValues(\.untyped) }
}

/// A dictionary of strings as the JSON values the legacy builder is fed.
private func strings(_ values: [String: String]) -> [String: JSONValue] {
    values.mapValues { .string($0) }
}

/// The wire shape of a server-driven config row.
private struct ServerConfig: Codable, Equatable, Sendable {
    struct Flags: Codable, Equatable, Sendable {
        let paywall: Bool
        let onboarding: Bool
        let beta: Bool
    }

    let id: String
    let appId: String
    let minVersion: String
    let latestVersion: String
    let killSwitch: Bool
    let maintenanceMode: Bool
    let maintenanceMessage: String?
    let featureFlags: Flags
    let configData: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id
        case appId = "app_id"
        case minVersion = "min_version"
        case latestVersion = "latest_version"
        case killSwitch = "kill_switch"
        case maintenanceMode = "maintenance_mode"
        case maintenanceMessage = "maintenance_message"
        case featureFlags = "feature_flags"
        case configData = "config_data"
    }
}

private enum ConfigFixtures {
    static let row = """
    {"id":"cfg000000000001","app_id":"demo","env":"prod","min_version":"1.2.0","latest_version":"1.4.0",\
    "kill_switch":false,"maintenance_mode":true,"maintenance_message":"back soon",\
    "feature_flags":{"paywall":true,"onboarding":true,"beta":false},"config_data":{"banner":"hello"}}
    """

    static let expected = ServerConfig(
        id: "cfg000000000001", appId: "demo", minVersion: "1.2.0", latestVersion: "1.4.0",
        killSwitch: false, maintenanceMode: true, maintenanceMessage: "back soon",
        featureFlags: .init(paywall: true, onboarding: true, beta: false), configData: ["banner": "hello"]
    )

    static let appId = "demo"
    static let env = "prod"
}

/// The composite answer of a custom bootstrap route.
private struct Bootstrap: Decodable, Sendable {
    struct Message: Decodable, Sendable {
        let id: String
        let title: String
    }

    let config: ServerConfig?
    let unreadMessages: [Message]
}

@Suite("PocketEndPoint — parity with the legacy app-level endpoints")
struct PocketParityTests {

    private let config: PocketConfig
    private let legacyBuilder = MockNetworkService()

    init() throws {
        config = try PocketFixtures.config()
    }

    /// Everything a server can see of a request, with the query decoded so the
    /// comparison does not depend on how a builder spelled its percent-encoding.
    private struct Wire: Equatable {
        let method: String
        let url: String
        let query: [String: String]
        let authorization: String?
        let accept: String?
        let body: Data?

        init(_ request: URLRequest) throws {
            method = request.httpMethod ?? ""
            let url = try #require(request.url)
            let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
            self.url = "\(components.scheme ?? "")://\(components.host ?? "")\(components.percentEncodedPath)"
            query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            authorization = request.value(forHTTPHeaderField: "Authorization")
            accept = request.value(forHTTPHeaderField: "Accept")
            body = request.httpBody
        }
    }

    private func legacy(
        _ method: RequestMethod, _ path: String, token: String? = nil,
        body: [String: JSONValue]? = nil, query: [String: JSONValue]? = nil
    ) throws -> Wire {
        var header = ["accept": "application/json"]
        if let token { header["Authorization"] = "Bearer \(token)" }
        let endpoint = LegacyEndPoint(method: method, path: path, header: header, bodyFields: body, queryFields: query)
        return try Wire(legacyBuilder.createRequest(endPoint: endpoint))
    }

    // MARK: Fetch config records (the standard-collection fallback)

    @Test("test_parity_configFallback_listWithFilter_isTheSameRequest")
    func test_parity_configFallback_listWithFilter_isTheSameRequest() throws {
        let before = try legacy(
            .GET, "collections/app_configs/records", token: PocketFixtures.token,
            query: strings(["filter": "(app_id='demo' && env='prod')", "perPage": "1"])
        )
        let query = PocketQuery(
            perPage: 1,
            filter: "(app_id=\(try PocketFilter.literal(ConfigFixtures.appId)) && env=\(try PocketFilter.literal(ConfigFixtures.env)))"
        )
        let after = try Wire(PocketEndPoint.list(config: config, collection: "app_configs", query: query, token: PocketFixtures.token).urlRequest())
        #expect(after.method == before.method)
        #expect(after.url == before.url)
        #expect(after.query == before.query)
        #expect(after.authorization == before.authorization)
        #expect(after.accept == before.accept)
    }

    @Test("test_parity_configFallback_throughTheClient_decodesTheFirstRow")
    func test_parity_configFallback_throughTheClient_decodesTheFirstRow() async throws {
        let transport = MockPocketTransport(replies: [.json(PocketFixtures.listJSON([ConfigFixtures.row], perPage: 1))])
        let client = PocketClient(config: config, transport: transport)
        let page: PocketListContainer<ServerConfig> = try await client.list(
            collection: "app_configs",
            query: PocketQuery(perPage: 1, filter: "(app_id='demo' && env='prod')"),
            token: PocketFixtures.token
        )
        #expect(page.items.first == ConfigFixtures.expected)
    }

    @Test("test_parity_configFallback_throughTheLegacyNetworkProtocol_stillWorks")
    func test_parity_configFallback_throughTheLegacyNetworkProtocol_stillWorks() async throws {
        // A consumer that calls `networkService.sendRequest(endpoint:)` today keeps
        // that call shape: PocketEndPoint is an EndPoint.
        let network = MockNetworkService()
        network.resultData = Data(PocketFixtures.listJSON([ConfigFixtures.row], perPage: 1).utf8)
        let endpoint = PocketEndPoint.list(
            config: config, collection: "app_configs",
            query: PocketQuery(perPage: 1, filter: "(app_id='demo' && env='prod')"), token: PocketFixtures.token
        )
        let page: PocketListContainer<ServerConfig> = try await network.sendRequest(endpoint: endpoint)
        #expect(page.items.first == ConfigFixtures.expected)

        let sent = try Wire(#require(network.capturedRequests.first))
        let direct = try Wire(endpoint.urlRequest())
        #expect(sent.method == direct.method)
        #expect(sent.url == direct.url)
        #expect(sent.query == direct.query)
        #expect(sent.authorization == direct.authorization)
    }

    // MARK: The custom bootstrap route

    @Test("test_parity_bootstrapRoute_isTheSameRequest")
    func test_parity_bootstrapRoute_isTheSameRequest() throws {
        let before = try legacy(
            .GET, "custom/app-bootstrap", token: PocketFixtures.token, query: strings(["app_id": "demo", "env": "prod"])
        )
        let after = try Wire(PocketEndPoint.route(
            config: config, path: "custom/app-bootstrap", query: ["app_id": "demo", "env": "prod"], token: PocketFixtures.token
        ).urlRequest())
        #expect(after.method == before.method)
        #expect(after.url == before.url)
        #expect(after.query == before.query)
        #expect(after.authorization == before.authorization)
    }

    @Test("test_parity_bootstrapRoute_throughTheClient_decodesTheCompositeAnswer")
    func test_parity_bootstrapRoute_throughTheClient_decodesTheCompositeAnswer() async throws {
        let answer = #"{"config":\#(ConfigFixtures.row),"userStatus":null,"unreadMessages":[{"id":"msg000000000001","title":"hi"}]}"#
        let transport = MockPocketTransport(replies: [.json(answer)])
        let client = PocketClient(config: config, transport: transport)
        let boot: Bootstrap = try await client.route("custom/app-bootstrap", query: ["app_id": "demo", "env": "prod"], token: PocketFixtures.token)
        #expect(boot.config == ConfigFixtures.expected)
        #expect(boot.unreadMessages.map(\.id) == ["msg000000000001"])
    }

    // MARK: Mark a message read

    private struct Read: Codable, Equatable { let is_read: Bool }

    @Test("test_parity_markMessageRead_isNowAPatch_becauseLegacyPutIsNotARoute")
    func test_parity_markMessageRead_isNowAPatch_becauseLegacyPutIsNotARoute() throws {
        // DELIBERATE DIFFERENCE. The legacy endpoint sent PUT ("PATCH semantics via
        // PUT"). PocketBase registers no PUT route for records: measured against a
        // live 0.25.9 and 0.40.6 server, PUT answers 404 and PATCH answers 200. The
        // path, token and body are unchanged; only the verb is corrected.
        let before = try legacy(.PUT, "collections/admin_messages/records/msg000000000001", token: PocketFixtures.token, body: ["is_read": .bool(true)])
        let after = try Wire(PocketEndPoint.update(
            config: config, collection: "admin_messages", id: "msg000000000001",
            payload: PocketPayload(fields: ["is_read": .bool(true)]), token: PocketFixtures.token
        ).urlRequest())
        #expect(before.method == "PUT")
        #expect(after.method == "PATCH")
        #expect(after.url == before.url)
        #expect(after.authorization == before.authorization)
        let sent = try JSONDecoder().decode(Read.self, from: try #require(after.body))
        let legacySent = try JSONDecoder().decode(Read.self, from: try #require(before.body))
        #expect(sent == legacySent)
    }

    // MARK: Auth flows

    private struct Credentials: Codable, Equatable { let identity: String; let password: String }
    private struct NewUser: Codable, Equatable {
        let email: String
        let emailVisibility: Bool
        let username: String
        let name: String
        let password: String
        let passwordConfirm: String
    }

    @Test("test_parity_login_isTheSameRequest_andNowLabelsItsBodyAsJson")
    func test_parity_login_isTheSameRequest_andNowLabelsItsBodyAsJson() throws {
        let before = try legacy(.POST, "collections/users/auth-with-password", body: strings(["identity": "ada@example.test", "password": "pw-123456"]))
        let afterRequest = try PocketEndPoint.authWithPassword(config: config, collection: "users", identity: "ada@example.test", password: "pw-123456").urlRequest()
        let after = try Wire(afterRequest)
        #expect(after.method == before.method)
        #expect(after.url == before.url)
        #expect(try JSONDecoder().decode(Credentials.self, from: #require(after.body)) == JSONDecoder().decode(Credentials.self, from: #require(before.body)))
        // DELIBERATE DIFFERENCE. The legacy builder never sets Content-Type, so
        // URLSession labels the JSON body application/x-www-form-urlencoded and
        // PocketBase answers "Cannot be blank" for identity and password (measured
        // live). This client always says it is JSON.
        #expect(afterRequest.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test("test_parity_legacyBuilder_sendsNoContentType_forABody")
    func test_parity_legacyBuilder_sendsNoContentType_forABody() throws {
        let request = legacyBuilder.createRequest(endPoint: LegacyEndPoint(
            method: .POST, path: "collections/users/auth-with-password", header: ["accept": "application/json"],
            bodyFields: strings(["identity": "i", "password": "p"]), queryFields: nil
        ))
        #expect(request.value(forHTTPHeaderField: "Content-Type") == nil)
    }

    @Test("test_parity_loginBodyThroughTheLegacyBuilder_isLabelledJson_whenTheEndpointIsAPocketEndPoint")
    func test_parity_loginBodyThroughTheLegacyBuilder_isLabelledJson_whenTheEndpointIsAPocketEndPoint() {
        let endpoint = PocketEndPoint.authWithPassword(config: config, collection: "users", identity: "i", password: "p")
        let request = legacyBuilder.createRequest(endPoint: endpoint)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/collections/users/auth-with-password")
    }

    @Test("test_parity_refresh_isTheSameRequest")
    func test_parity_refresh_isTheSameRequest() throws {
        let before = try legacy(.POST, "collections/users/auth-refresh", token: PocketFixtures.token)
        let after = try Wire(PocketEndPoint.authRefresh(config: config, collection: "users", token: PocketFixtures.token).urlRequest())
        #expect(after.method == before.method)
        #expect(after.url == before.url)
        #expect(after.authorization == before.authorization)
        #expect(after.body == nil && before.body == nil)
    }

    @Test("test_parity_passwordReset_isTheSameRequest")
    func test_parity_passwordReset_isTheSameRequest() throws {
        struct Email: Codable, Equatable { let email: String }
        let before = try legacy(.POST, "collections/users/request-password-reset", body: strings(["email": "ada@example.test"]))
        let after = try Wire(PocketEndPoint.requestPasswordReset(config: config, collection: "users", email: "ada@example.test").urlRequest())
        #expect(after.url == before.url)
        #expect(try JSONDecoder().decode(Email.self, from: #require(after.body)) == JSONDecoder().decode(Email.self, from: #require(before.body)))
    }

    @Test("test_parity_register_isACreateOnTheUsersCollection")
    func test_parity_register_isACreateOnTheUsersCollection() throws {
        let fields = NewUser(
            email: "ada@example.test", emailVisibility: true, username: "ada", name: "Ada",
            password: "pw-123456", passwordConfirm: "pw-123456"
        )
        let before = try legacy(.POST, "collections/users/records", body: [
            "email": .string(fields.email), "emailVisibility": .bool(true), "username": .string(fields.username),
            "name": .string(fields.name), "password": .string(fields.password), "passwordConfirm": .string(fields.passwordConfirm),
        ])
        let after = try Wire(PocketEndPoint.create(config: config, collection: "users", payload: PocketPayload(fields)).urlRequest())
        #expect(after.method == before.method)
        #expect(after.url == before.url)
        #expect(try JSONDecoder().decode(NewUser.self, from: #require(after.body)) == fields)
        #expect(try JSONDecoder().decode(NewUser.self, from: #require(before.body)) == fields)
    }

    // MARK: Plain list and relation list

    @Test("test_parity_list_legacyDefaultsArePassedExplicitly")
    func test_parity_list_legacyDefaultsArePassedExplicitly() throws {
        // The legacy `.list` injected perPage 20, page 1 and sort "-created,username".
        // Those were that app's choices, not PocketBase's; the generic client sends
        // nothing it was not told to, so the app passes them.
        let before = try legacy(.GET, "collections/users/records", query: strings(["perPage": "20", "page": "1", "sort": "-created,username"]))
        let after = try Wire(PocketEndPoint.list(
            config: config, collection: "users", query: PocketQuery(page: 1, perPage: 20, sort: "-created,username")
        ).urlRequest())
        #expect(after.url == before.url)
        #expect(after.query == before.query)

        let bare = try Wire(PocketEndPoint.list(config: config, collection: "users").urlRequest())
        #expect(bare.query.isEmpty)
    }

    @Test("test_parity_relationList_filterSortAndExpand_areTheSameRequest")
    func test_parity_relationList_filterSortAndExpand_areTheSameRequest() throws {
        let before = try legacy(.GET, "collections/relations/records", query: strings([
            "perPage": "20", "page": "1", "filter": "(owner.id='own000000000001')",
            "sort": "-created,type,user.username", "expand": "owner,user",
        ]))
        let owner = try PocketFilter.literal("own000000000001")
        let after = try Wire(PocketEndPoint.list(
            config: config, collection: "relations",
            query: PocketQuery(page: 1, perPage: 20, sort: "-created,type,user.username", filter: "(owner.id=\(owner))", expand: "owner,user")
        ).urlRequest())
        #expect(after.url == before.url)
        #expect(after.query == before.query)
    }

    @Test("test_parity_detail_isTheSameRequest")
    func test_parity_detail_isTheSameRequest() throws {
        let before = try legacy(.GET, "collections/relations/records/rel000000000001", query: [:])
        let after = try Wire(PocketEndPoint.view(config: config, collection: "relations", id: "rel000000000001").urlRequest())
        #expect(after.url == before.url)
        #expect(after.query == before.query)
    }

    // MARK: What the legacy builder gets wrong

    @Test("test_parity_legacyBuilder_turnsANonStringQueryValueIntoADash")
    func test_parity_legacyBuilder_turnsANonStringQueryValueIntoADash() throws {
        // `[URLQueryItem](from:)` writes "-" for anything that is not a String, so an
        // Int perPage silently becomes "-". PocketQuery is typed and cannot.
        let legacyWire = try legacy(.GET, "collections/users/records", query: ["perPage": .integer(20)])
        #expect(legacyWire.query["perPage"] == "-")
        let typed = try Wire(PocketEndPoint.list(config: config, collection: "users", query: PocketQuery(perPage: 20)).urlRequest())
        #expect(typed.query["perPage"] == "20")
    }
}

//
//  PocketConfigEndpointTests.swift
//  NetworkKitTests
//
//  PocketConfigEndpoint is a CoreKit `ConfigEndpoint`. CoreKit's own
//  conformance suite runs over it here against a fake server, and — in the
//  live scope — against a real PocketBase.
//

import CoreKit
import CoreKitTestSupport
import Foundation
import Testing
@testable import NetKit

@Suite("PocketConfigEndpoint — CoreKit's ConfigEndpoint over PocketBase")
struct PocketConfigEndpointTests {

    private let query = AppConfigQuery(appId: "demo", environment: "prod")
    private let unknown = AppConfigQuery(appId: "ghost", environment: "prod")

    private func makeSUT() async throws -> (endpoint: PocketConfigEndpoint, server: FakeConfigServer) {
        let server = FakeConfigServer()
        await server.seed(ConfigEndpointConformance.sampleConfig(for: query), environment: query.environment)
        let client = PocketClient(config: try PocketFixtures.config(), transport: server)
        return (PocketConfigEndpoint(client: client, collection: "app_configs") { PocketFixtures.token }, server)
    }

    // MARK: Conformance

    @Test("test_conformance_everyCheck_passesOverTheFakeServer", arguments: ConfigEndpointConformance.Check.allCases)
    func test_conformance_everyCheck_passesOverTheFakeServer(_ check: ConfigEndpointConformance.Check) async throws {
        let (endpoint, _) = try await makeSUT()
        let harness = ConfigEndpointHarness(
            label: "PocketConfigEndpoint(fake)", endpoint: endpoint, query: query,
            expected: ConfigEndpointConformance.sampleConfig(for: query), unknownQuery: unknown
        )
        let violations = await ConfigEndpointConformance.run(check, on: harness)
        #expect(violations.isEmpty, "\(violations)")
    }

    @Test("test_conformance_runAll_hasNoViolations")
    func test_conformance_runAll_hasNoViolations() async throws {
        let (endpoint, _) = try await makeSUT()
        let harness = ConfigEndpointHarness(
            label: "PocketConfigEndpoint(fake)", endpoint: endpoint, query: query,
            expected: ConfigEndpointConformance.sampleConfig(for: query), unknownQuery: unknown
        )
        #expect(await ConfigEndpointConformance.runAll(on: harness).isEmpty)
    }

    // MARK: The request

    @Test("test_fetch_asksForOneRecordFilteredByAppAndEnvironment_withTheCurrentToken")
    func test_fetch_asksForOneRecordFilteredByAppAndEnvironment_withTheCurrentToken() async throws {
        let transport = MockPocketTransport(replies: [.json(PocketFixtures.listJSON([]))])
        let endpoint = PocketConfigEndpoint(client: PocketClient(config: try PocketFixtures.config(), transport: transport), collection: "app_configs") { PocketFixtures.token }
        _ = try? await endpoint.fetchConfig(query)
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/api/collections/app_configs/records")
        #expect(try queryValue("filter", in: request) == "(app_id='demo' && env='prod')")
        #expect(try queryValue("perPage", in: request) == "1")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(PocketFixtures.token)")
    }

    @Test("test_fetch_withoutAToken_isAnonymous")
    func test_fetch_withoutAToken_isAnonymous() async throws {
        let transport = MockPocketTransport(replies: [.json(PocketFixtures.listJSON([]))])
        let endpoint = PocketConfigEndpoint(client: PocketClient(config: try PocketFixtures.config(), transport: transport), collection: "app_configs")
        _ = try? await endpoint.fetchConfig(query)
        let request = try #require(await transport.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("test_fetch_aValueWithAQuote_isEscaped_notInjected")
    func test_fetch_aValueWithAQuote_isEscaped_notInjected() async throws {
        let transport = MockPocketTransport(replies: [.json(PocketFixtures.listJSON([]))])
        let endpoint = PocketConfigEndpoint(client: PocketClient(config: try PocketFixtures.config(), transport: transport), collection: "app_configs")
        _ = try? await endpoint.fetchConfig(AppConfigQuery(appId: "x' || app_id != '", environment: "prod"))
        let request = try #require(await transport.requests.first)
        let filter = try queryValue("filter", in: request)
        #expect(filter == #"(app_id='x\' || app_id != \'' && env='prod')"#)
    }

    @Test("test_fetch_aBackslashInTheQuery_isRefused_andNothingIsSent")
    func test_fetch_aBackslashInTheQuery_isRefused_andNothingIsSent() async throws {
        let transport = MockPocketTransport()
        let endpoint = PocketConfigEndpoint(client: PocketClient(config: try PocketFixtures.config(), transport: transport), collection: "app_configs")
        do {
            _ = try await endpoint.fetchConfig(AppConfigQuery(appId: #"a\b"#, environment: "prod"))
            Issue.record("expected a refusal")
        } catch let error as PocketError {
            guard case .invalidRequest = error else { Issue.record("expected .invalidRequest, got \(error)"); return }
        }
        #expect(await transport.requests.isEmpty)
    }

    // MARK: Answers

    @Test("test_fetch_anEmptyPage_isConfigEndpointErrorNotFound_carryingTheQuery")
    func test_fetch_anEmptyPage_isConfigEndpointErrorNotFound_carryingTheQuery() async throws {
        let transport = MockPocketTransport(replies: [.json(PocketFixtures.listJSON([]))])
        let endpoint = PocketConfigEndpoint(client: PocketClient(config: try PocketFixtures.config(), transport: transport), collection: "app_configs")
        do {
            _ = try await endpoint.fetchConfig(query)
            Issue.record("expected notFound")
        } catch let error as ConfigEndpointError {
            #expect(error == .notFound(query))
        }
    }

    @Test("test_fetch_aServerFailure_isThrownUnchanged_asAPocketError")
    func test_fetch_aServerFailure_isThrownUnchanged_asAPocketError() async throws {
        let transport = MockPocketTransport(replies: [.json(status: 401, #"{"data":{},"message":"The request requires valid record authorization token.","status":401}"#)])
        let endpoint = PocketConfigEndpoint(client: PocketClient(config: try PocketFixtures.config(), transport: transport), collection: "app_configs")
        do {
            _ = try await endpoint.fetchConfig(query)
            Issue.record("expected a throw")
        } catch let error as PocketError {
            guard case .authentication(let failure) = error else { Issue.record("expected .authentication, got \(error)"); return }
            #expect(failure.body?.message == "The request requires valid record authorization token.")
        }
    }

    @Test("test_fetch_theSnakeCaseRecord_decodesEveryField")
    func test_fetch_theSnakeCaseRecord_decodesEveryField() async throws {
        let record = """
        {"id":"cfg000000000001","collectionId":"pbc_1","collectionName":"app_configs","app_id":"demo","env":"prod",\
        "min_version":"1.2.0","latest_version":"1.4.1","kill_switch":true,"maintenance_mode":false,\
        "maintenance_message":"","feature_flags":{"a":true,"n":3},"config_data":null}
        """
        let transport = MockPocketTransport(replies: [.json(PocketFixtures.listJSON([record], perPage: 1))])
        let endpoint = PocketConfigEndpoint(client: PocketClient(config: try PocketFixtures.config(), transport: transport), collection: "app_configs")
        let config = try await endpoint.fetchConfig(query)
        #expect(config.id == "cfg000000000001")
        #expect(config.minVersion == "1.2.0")
        #expect(config.killSwitch)
        #expect(config.featureFlags == RemoteFeatureFlags(["a": .bool(true), "n": .int(3)]))
        #expect(config.configData == nil)
        #expect(config.block == .killSwitch(message: ""))
    }

    // MARK: The service above it

    @Test("test_service_bootstrap_overThePocketEndpoint_fetchesAndCaches")
    func test_service_bootstrap_overThePocketEndpoint_fetchesAndCaches() async throws {
        let (endpoint, _) = try await makeSUT()
        let cache = InMemoryRepository<String, AppConfig>()
        let service = AppConfigService(query: query, endpoint: endpoint, cache: cache)
        #expect(await service.bootstrap() == .fetched)
        #expect(await service.currentConfig == ConfigEndpointConformance.sampleConfig(for: query))
        #expect(await service.block == .maintenance(message: "Back shortly — é"))
        #expect(await cache.saveCount == 1)
    }

    @Test("test_service_bootstrap_whenThePocketServerAnswersNothing_usesTheCache")
    func test_service_bootstrap_whenThePocketServerAnswersNothing_usesTheCache() async throws {
        let cache = InMemoryRepository<String, AppConfig>()
        try await cache.save(query.storageKey, data: ConfigEndpointConformance.sampleConfig(for: query))
        let transport = MockPocketTransport(replies: [.failure(URLError(.notConnectedToInternet))])
        let endpoint = PocketConfigEndpoint(client: PocketClient(config: try PocketFixtures.config(), transport: transport), collection: "app_configs")
        let service = AppConfigService(query: query, endpoint: endpoint, cache: cache)
        #expect(await service.bootstrap() == .usingCache)
        #expect(await service.currentConfig == ConfigEndpointConformance.sampleConfig(for: query))
    }
}

//
//  PocketConfigLiveTests.swift
//  NetworkKitTests
//
//  PocketConfigEndpoint against a REAL PocketBase, under CoreKit's own
//  `ConfigEndpointConformance` suite, seeded with its `sampleConfig(for:)`.
//  Run through `scripts/pocketbase-live.sh`, like the rest of the live scope.
//

import CoreKit
import CoreKitTestSupport
import Foundation
import Testing
@testable import NetKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite("PocketConfigEndpoint — live, under CoreKit's ConfigEndpointConformance", .serialized)
struct PocketConfigLiveTests {

    private let query = AppConfigQuery(appId: "demo", environment: "prod")
    private let unknown = AppConfigQuery(appId: "ghost", environment: "prod")

    /// A live collection holding `sampleConfig(for: query)`. The server assigns the
    /// record id, so the expected configuration is the sample with that id.
    private func seeded(on server: LiveServer, listRule: String? = "") async throws -> (collection: String, expected: AppConfig) {
        let name = "netkit_app_configs_\(LiveServer.suffix())"
        try await server.createCollection(.appConfigs(name: name, listRule: listRule))

        let sample = ConfigEndpointConformance.sampleConfig(for: query)
        var fields = try PocketPayload(sample).fields
        fields["id"] = nil
        fields["env"] = .string(query.environment)
        let created: AppConfig = try await server.client.create(
            collection: name, payload: PocketPayload(fields: fields), token: server.adminToken
        )

        let expected = AppConfig(
            id: created.id, appId: sample.appId, minVersion: sample.minVersion, latestVersion: sample.latestVersion,
            killSwitch: sample.killSwitch, maintenanceMode: sample.maintenanceMode, maintenanceMessage: sample.maintenanceMessage,
            featureFlags: sample.featureFlags, configData: sample.configData
        )
        #expect(created == expected, "the server stored and returned exactly what the sample says")
        return (name, expected)
    }

    @Test("test_live_conformance_everyCheck_passesOverARealPocketBase", arguments: ConfigEndpointConformance.Check.allCases)
    func test_live_conformance_everyCheck_passesOverARealPocketBase(_ check: ConfigEndpointConformance.Check) async throws {
        let server = try await LiveServer.connect()
        let (collection, expected) = try await seeded(on: server)
        let harness = ConfigEndpointHarness(
            label: "PocketConfigEndpoint(live)", endpoint: PocketConfigEndpoint(client: server.client, collection: collection),
            query: query, expected: expected, unknownQuery: unknown
        )
        let violations = await ConfigEndpointConformance.run(check, on: harness)
        #expect(violations.isEmpty, "\(violations)")
    }

    @Test("test_live_conformance_runAll_hasNoViolations")
    func test_live_conformance_runAll_hasNoViolations() async throws {
        let server = try await LiveServer.connect()
        let (collection, expected) = try await seeded(on: server)
        let harness = ConfigEndpointHarness(
            label: "PocketConfigEndpoint(live)", endpoint: PocketConfigEndpoint(client: server.client, collection: collection),
            query: query, expected: expected, unknownQuery: unknown
        )
        #expect(await ConfigEndpointConformance.runAll(on: harness).isEmpty)
    }

    @Test("test_live_aLockedCollection_refusesAnonymous_andTheTokenProviderOpensIt")
    func test_live_aLockedCollection_refusesAnonymous_andTheTokenProviderOpensIt() async throws {
        let server = try await LiveServer.connect()
        let (collection, expected) = try await seeded(on: server, listRule: nil)

        // Anonymous: PocketBase answers 403, and the endpoint throws it unchanged.
        let anonymous = PocketConfigEndpoint(client: server.client, collection: collection)
        do {
            _ = try await anonymous.fetchConfig(query)
            Issue.record("expected the locked collection to refuse an anonymous read")
        } catch let error as PocketError {
            guard case .authentication(let failure) = error else { Issue.record("expected .authentication, got \(error)"); return }
            #expect(failure.status == 403)
        }

        // With the token the provider supplies, it answers.
        let token = server.adminToken
        let authorised = PocketConfigEndpoint(client: server.client, collection: collection) { token }
        #expect(try await authorised.fetchConfig(query) == expected)
    }

    @Test("test_live_hostileQueryValues_areNeitherInjectedNorMatched")
    func test_live_hostileQueryValues_areNeitherInjectedNorMatched() async throws {
        let server = try await LiveServer.connect()
        let (collection, _) = try await seeded(on: server)
        let endpoint = PocketConfigEndpoint(client: server.client, collection: collection)
        let hostile = AppConfigQuery(appId: "zzz' || app_id != '", environment: "prod")
        do {
            _ = try await endpoint.fetchConfig(hostile)
            Issue.record("a hostile app id must not match the seeded record")
        } catch let error as ConfigEndpointError {
            #expect(error == .notFound(hostile))
        }
    }

    @Test("test_live_appConfigService_bootstrapsOverARealPocketBase_andCaches")
    func test_live_appConfigService_bootstrapsOverARealPocketBase_andCaches() async throws {
        let server = try await LiveServer.connect()
        let (collection, expected) = try await seeded(on: server)
        let cache = InMemoryRepository<String, AppConfig>()
        let service = AppConfigService(
            query: query, endpoint: PocketConfigEndpoint(client: server.client, collection: collection), cache: cache
        )
        #expect(await service.bootstrap() == .fetched)
        #expect(await service.currentConfig == expected)
        #expect(await service.block == .maintenance(message: "Back shortly — é"))
        #expect(try await cache.get(query.storageKey) == expected)
    }
}

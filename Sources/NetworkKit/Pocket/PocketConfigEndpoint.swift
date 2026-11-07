//
//  PocketConfigEndpoint.swift
//  NetworkKit
//
//  The PocketBase backing of CoreKit's `ConfigEndpoint` (spec d3f8a1b2,
//  BR-RP-13). CoreKit owns the contract and the `AppConfig` it answers with;
//  this type owns only how to ask PocketBase for it. A server that runs on SQL
//  or a settings file answers the same question through the same protocol, so
//  the service above never learns which one it has.
//

import CoreKit
import Foundation

/// Reads the server-driven ``AppConfig`` from a PocketBase collection.
///
/// ```swift
/// let endpoint = PocketConfigEndpoint(client: client, collection: "app_configs") { await session.token }
/// let service = AppConfigService(query: AppConfigQuery(appId: "demo", environment: "prod"),
///                                endpoint: endpoint, cache: cache)
/// ```
///
/// The collection holds one record per app and environment, with the
/// snake_case fields ``AppConfig`` decodes (`app_id`, `min_version`,
/// `latest_version`, `kill_switch`, `maintenance_mode`, `maintenance_message`,
/// `feature_flags`, `config_data`) plus an `env` text field the query filters
/// on. Its name is injected: this type knows no app's collection.
public struct PocketConfigEndpoint: ConfigEndpoint {
    private let client: any PocketClientProtocol
    private let collection: String
    private let token: @Sendable () async -> String?

    /// - Parameters:
    ///   - client: The PocketBase client to ask through.
    ///   - collection: The collection that holds the configuration records.
    ///   - token: Supplies the bearer token for each fetch (a login's token
    ///     changes when it is refreshed, so it is asked for, not stored).
    ///     `nil` result: the fetch uses the client's configured credential, or
    ///     none.
    public init(
        client: any PocketClientProtocol,
        collection: String,
        token: @escaping @Sendable () async -> String? = { nil }
    ) {
        self.client = client
        self.collection = collection
        self.token = token
    }

    /// - Throws: ``ConfigEndpointError/notFound(_:)`` when the collection holds
    ///   no record for the query; ``PocketError`` (unchanged) for everything
    ///   else the server or the transport raises, a rejected token included.
    public func fetchConfig(_ query: AppConfigQuery) async throws -> AppConfig {
        let filter = try "(app_id=\(PocketFilter.literal(query.appId)) && env=\(PocketFilter.literal(query.environment)))"
        let page: PocketListContainer<AppConfig> = try await client.list(
            collection: collection,
            query: PocketQuery(perPage: 1, filter: filter),
            token: await token()
        )
        guard let config = page.items.first else { throw ConfigEndpointError.notFound(query) }
        return config
    }
}

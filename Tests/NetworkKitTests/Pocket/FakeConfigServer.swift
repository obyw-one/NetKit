//
//  FakeConfigServer.swift
//  NetworkKitTests
//
//  A PocketBase that only knows how to list a configuration collection: it
//  reads the `app_id` / `env` filter the endpoint sends, looks the pair up in
//  what it was seeded with and answers with PocketBase's list envelope. It lets
//  the SAME conformance suite that runs against a real server run offline.
//

import CoreKit
import Foundation
import Testing
@testable import NetKit

actor FakeConfigServer: PocketTransport {
    struct Row {
        let config: AppConfig
        let environment: String
    }

    private var rows: [String: Row] = [:]
    private(set) var requests: [URLRequest] = []

    func seed(_ config: AppConfig, environment: String) {
        rows["\(config.appId)|\(environment)"] = Row(config: config, environment: environment)
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let url = try #require(request.url)
        let filter = try #require(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "filter" }?.value,
            "the endpoint sent no filter"
        )
        let match = try #require(filter.firstMatch(of: /\(app_id='((?:[^'\\]|\\.)*)' && env='((?:[^'\\]|\\.)*)'\)/), "unrecognised filter \(filter)")
        let appId = String(match.1).replacingOccurrences(of: "\\'", with: "'")
        let environment = String(match.2).replacingOccurrences(of: "\\'", with: "'")

        var items: [String] = []
        if let row = rows["\(appId)|\(environment)"] {
            var fields = try PocketPayload(row.config).fields
            fields["env"] = .string(row.environment)
            fields["collectionName"] = .string("app_configs")
            items.append(try utf8Text(PocketPayload(fields: fields).jsonData()))
        }
        let body = PocketFixtures.listJSON(items, perPage: 1)
        let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil))
        return (Data(body.utf8), response)
    }
}

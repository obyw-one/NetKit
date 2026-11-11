//
//  PocketLiveSupport.swift
//  NetworkKitTests
//
//  Support for the REAL round trip against a throwaway PocketBase. The server,
//  its superuser and its port are created by `scripts/pocketbase-live.sh` and
//  handed to the tests through the environment; nothing here knows a hostname
//  or holds a credential of its own.
//
//  Environment keys are declared as a typed enum and read through CoreKit's
//  `TypedEnvironment` — the same shape BackendKit's live suites use — never by a
//  raw `ProcessInfo` read.
//

import CoreKit
import Foundation
import Testing
@testable import NetKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum LiveEnvKey: String, EnvironmentKey {
    case url = "NETKIT_POCKETBASE_URL"
    case adminEmail = "NETKIT_POCKETBASE_ADMIN_EMAIL"
    case adminPassword = "NETKIT_POCKETBASE_ADMIN_PASSWORD"
}

enum LiveEnv {
    /// A required live-server setting. A missing one FAILS the test with the
    /// instruction to use the script — it never skips (see `PocketLiveTests`).
    static func value(_ key: LiveEnvKey) throws -> String {
        guard let value = TypedEnvironment.current()[key] else { throw LiveError.missing(key.rawValue) }
        return value
    }
}

enum LiveError: Error, CustomStringConvertible {
    case missing(String)
    case unexpectedStatus(Int, String)

    var description: String {
        switch self {
        case .missing(let name): return "\(name) is not set: run these tests through scripts/pocketbase-live.sh"
        case .unexpectedStatus(let status, let what): return "\(what) answered \(status)"
        }
    }
}

// MARK: - Wire shapes the tests share with the server

struct Superuser: Codable, Equatable, Sendable {
    let id: String
    let email: String
}

struct LiveNote: Codable, Equatable, Sendable {
    let id: String
    let title: String
    let done: Bool
    let score: Int
    let due: Date?
    let created: Date

    private enum CodingKeys: String, CodingKey {
        case id, title, done, score, due, created
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        done = try container.decode(Bool.self, forKey: .done)
        score = try container.decode(Int.self, forKey: .score)
        // PocketBase writes an unset date as "": the plain Date? decoder would throw.
        due = try container.decodePocketDateIfPresent(forKey: .due)
        created = try container.decode(Date.self, forKey: .created)
    }
}

/// The same record, decoded the naive way: a plain `Date?`.
struct NaiveLiveNote: Decodable, Sendable {
    let id: String
    let due: Date?
}

/// What PocketBase answers to a registration: the email is hidden from everyone
/// but the record's owner, so it is NOT in this answer.
struct LiveRegistered: Decodable, Equatable, Sendable {
    let id: String
    let verified: Bool
}

struct LiveNoteDraft: Codable, Equatable, Sendable {
    let title: String
    let done: Bool
    let score: Int
    let due: Date?
}

struct LiveAuthor: Codable, Equatable, Sendable {
    let id: String
    let name: String
}

struct LiveNoteDraftWithAuthor: Codable, Equatable, Sendable {
    let title: String
    let score: Int
    let author: String
}

struct LiveNoteWithAuthor: Decodable, Equatable, Sendable {
    struct Expanded: Decodable, Equatable, Sendable {
        let author: LiveAuthor
    }

    let id: String
    let title: String
    let score: Int
    let expand: Expanded?
}

struct LiveAccountDraft: Codable, Equatable, Sendable {
    let email: String
    let password: String
    let passwordConfirm: String
}

struct LiveHealth: Decodable, Equatable, Sendable {
    let code: Int
    let message: String
}

/// Only the part of a PocketBase request-log row the tests assert on.
struct LiveLogRow: Decodable, Sendable {
    let method: String?
    let url: String?
    let status: Int?
}

struct LiveLogItem: Decodable, Sendable {
    let data: LiveLogRow
}

struct LiveLogPage: Decodable, Sendable {
    let items: [LiveLogItem]
}

// MARK: - Collection creation (admin API, test-only)

struct CollectionSpec: Encodable {
    struct Field: Encodable {
        let name: String
        let type: String
        var required: Bool?
        var onCreate: Bool?
        var onUpdate: Bool?
        var collectionId: String?
        var maxSelect: Int?
    }

    struct Created: Decodable {
        let id: String
        let name: String
    }

    let name: String
    let type = "base"
    let listRule: String?
    let viewRule: String?
    let createRule: String?
    let updateRule: String?
    let deleteRule: String?
    let fields: [Field]

    /// Public read/write rules; `createRule`/`updateRule`/`deleteRule` can be locked to a signed-in user.
    static func notes(name: String, writeRule: String = "", authorsID: String? = nil) -> CollectionSpec {
        var fields: [Field] = [
            Field(name: "title", type: "text", required: true),
            Field(name: "done", type: "bool"),
            Field(name: "score", type: "number"),
            Field(name: "due", type: "date"),
            Field(name: "created", type: "autodate", onCreate: true),
        ]
        if let authorsID { fields.append(Field(name: "author", type: "relation", collectionId: authorsID, maxSelect: 1)) }
        return CollectionSpec(
            name: name, listRule: "", viewRule: "", createRule: writeRule, updateRule: writeRule, deleteRule: writeRule, fields: fields
        )
    }

    /// A server-driven configuration collection: the snake_case fields `AppConfig` decodes, plus `env`.
    static func appConfigs(name: String, listRule: String?) -> CollectionSpec {
        CollectionSpec(
            name: name, listRule: listRule, viewRule: listRule, createRule: nil, updateRule: nil, deleteRule: nil,
            fields: [
                Field(name: "app_id", type: "text", required: true),
                Field(name: "env", type: "text", required: true),
                Field(name: "min_version", type: "text", required: true),
                Field(name: "latest_version", type: "text", required: true),
                Field(name: "kill_switch", type: "bool"),
                Field(name: "maintenance_mode", type: "bool"),
                Field(name: "maintenance_message", type: "text"),
                Field(name: "feature_flags", type: "json", required: true),
                Field(name: "config_data", type: "json"),
            ]
        )
    }

    static func authors(name: String) -> CollectionSpec {
        CollectionSpec(
            name: name, listRule: "", viewRule: "", createRule: "", updateRule: "", deleteRule: "",
            fields: [Field(name: "name", type: "text", required: true)]
        )
    }
}

// MARK: - The live server

/// A connection to the throwaway server with a superuser session.
///
/// The superuser logs in through the client under test, so every live test also
/// exercises `authWithPassword` against a real `_superusers` collection.
struct LiveServer: Sendable {
    let config: PocketConfig
    let client: PocketClient
    let adminToken: String
    let baseURL: URL

    static func connect() async throws -> LiveServer {
        let url = try #require(URL(string: try LiveEnv.value(.url)), "NETKIT_POCKETBASE_URL is not a URL")
        let config = try PocketConfig(endpoint: url, allowInsecureHTTP: true)
        let client = PocketClient(config: config)
        let session: PocketAuthResponse<Superuser> = try await client.authWithPassword(
            collection: "_superusers",
            identity: try LiveEnv.value(.adminEmail),
            password: try LiveEnv.value(.adminPassword)
        )
        return LiveServer(config: config, client: client, adminToken: session.token, baseURL: url)
    }

    /// A short random suffix so tests never share a collection or an account.
    static func suffix() -> String {
        String(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(10))
    }

    @discardableResult
    func createCollection(_ spec: CollectionSpec) async throws -> CollectionSpec.Created {
        let body = try JSONEncoder().encode(spec)
        let (status, data) = try await raw("POST", "/api/collections", body: body, token: adminToken)
        guard (200..<300).contains(status) else { throw LiveError.unexpectedStatus(status, "POST /api/collections") }
        return try JSONDecoder().decode(CollectionSpec.Created.self, from: data)
    }

    /// A request that bypasses the client under test, so a test can ask the server
    /// what it holds without trusting the code it is testing.
    func raw(_ method: String, _ pathAndQuery: String, body: Data? = nil, token: String? = nil) async throws -> (status: Int, data: Data) {
        let url = try #require(URL(string: pathAndQuery, relativeTo: baseURL)?.absoluteURL)
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token { request.setValue(token, forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = try #require(response as? HTTPURLResponse)
        return (http.statusCode, data)
    }

    /// The server's own request log rows whose URL contains `fragment`.
    func logRows(containing fragment: String) async throws -> [LiveLogRow] {
        let (status, data) = try await raw("GET", "/api/logs?perPage=500&sort=-created", token: adminToken)
        guard status == 200 else { throw LiveError.unexpectedStatus(status, "GET /api/logs") }
        return try JSONDecoder().decode(LiveLogPage.self, from: data).items
            .map(\.data)
            .filter { $0.url?.contains(fragment) == true }
    }
}

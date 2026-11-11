//
//  PocketLiveTests.swift
//  NetworkKitTests
//
//  The REAL round trip: PocketClient against a throwaway PocketBase started by
//  `scripts/pocketbase-live.sh`. Create a collection, create / list / view /
//  update / delete records, log in, refresh, reset a password, hit every error
//  path the server can produce — and then ask the SERVER, through its own
//  request log and through requests that bypass the client under test, whether
//  it really received those calls.
//
//  Run with:
//      scripts/pocketbase-live.sh -- kagami test --scope NetKitPocketLiveTests --strict
//
//  Without the script these tests FAIL, by design, with the instruction to use
//  it. They do not skip: measured with kagami, an all-skipped scope reports
//  `0/18` and exits 0 — skipped rows count toward the floor — so a skip would
//  read as a green gate that proved nothing.
//

import CoreKit
import Foundation
import Testing
@testable import NetKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One call the server's own request log must show.
private struct ExpectedCall {
    let method: String
    let urlPrefix: String
    let status: Int
}

@Suite("PocketClient — live round trip against a throwaway PocketBase", .serialized)
struct PocketLiveTests {

    // MARK: Records

    @Test("test_live_superuser_logsInThroughTheClientUnderTest")
    func test_live_superuser_logsInThroughTheClientUnderTest() async throws {
        let server = try await LiveServer.connect()
        let session: PocketAuthResponse<Superuser> = try await server.client.authWithPassword(
            collection: "_superusers",
            identity: try LiveEnv.value(.adminEmail),
            password: try LiveEnv.value(.adminPassword)
        )
        #expect(!session.token.isEmpty)
        #expect(session.record.id.count == 15)
        #expect(session.record.email == (try LiveEnv.value(.adminEmail)))
    }

    @Test("test_live_records_createListViewUpdateDelete")
    func test_live_records_createListViewUpdateDelete() async throws {
        let server = try await LiveServer.connect()
        let name = "netkit_notes_\(LiveServer.suffix())"
        try await server.createCollection(.notes(name: name))

        // create
        let created: LiveNote = try await server.client.create(
            collection: name, record: LiveNoteDraft(title: "first", done: false, score: 1, due: nil)
        )
        #expect(created.id.count == 15)
        #expect(created.title == "first")
        #expect(created.due == nil, "an unset date comes back as \"\" and decodes to nil through decodePocketDateIfPresent")
        #expect(created.created.timeIntervalSinceNow > -60, "the server's own timestamp decodes through the fleet strategy")

        // list
        let page: PocketListContainer<LiveNote> = try await server.client.list(collection: name)
        #expect(page.items.map(\.id) == [created.id])
        #expect(page.totalItems == 1)
        #expect(page.totalPages == 1)
        #expect(page.page == 1)

        // view
        let viewed: LiveNote = try await server.client.view(collection: name, id: created.id)
        #expect(viewed == created)

        // update: PATCH
        let updated: LiveNote = try await server.client.update(
            collection: name, id: created.id, payload: PocketPayload(fields: ["done": .bool(true), "score": .integer(7)])
        )
        #expect(updated.done)
        #expect(updated.score == 7)
        #expect(updated.title == "first", "a PATCH leaves the fields it did not name alone")

        // delete, then the server no longer has it
        try await server.client.delete(collection: name, id: created.id)
        let error = await thrownError { () async throws(PocketError) -> LiveNote in
            try await server.client.view(collection: name, id: created.id)
        }
        guard case .http(let failure)? = error else { Issue.record("expected .http, got \(String(describing: error))"); return }
        #expect(failure.status == 404)
        #expect(failure.body?.message == "The requested resource wasn't found.")
    }

    @Test("test_live_list_filterSortPaginationExpandAndSkipTotal")
    func test_live_list_filterSortPaginationExpandAndSkipTotal() async throws {
        let server = try await LiveServer.connect()
        let suffix = LiveServer.suffix()
        let authors = try await server.createCollection(.authors(name: "netkit_authors_\(suffix)"))
        let notes = "netkit_notes_\(suffix)"
        try await server.createCollection(.notes(name: notes, authorsID: authors.id))

        let ada: LiveAuthor = try await server.client.create(collection: authors.name, record: ["name": "Ada"])
        for score in 1...5 {
            let _: LiveNoteWithAuthor = try await server.client.create(
                collection: notes, record: LiveNoteDraftWithAuthor(title: "note \(score)", score: score, author: ada.id)
            )
        }

        // pagination + sort + totals
        let second: PocketListContainer<LiveNoteWithAuthor> = try await server.client.list(
            collection: notes, query: PocketQuery(page: 2, perPage: 2, sort: "-score")
        )
        #expect(second.items.map(\.score) == [3, 2])
        #expect(second.page == 2)
        #expect(second.perPage == 2)
        #expect(second.totalItems == 5)
        #expect(second.totalPages == 3)

        // filter built with the safe literal
        let filter = "score >= 4 && title != \(try PocketFilter.literal("note 5"))"
        let filtered: PocketListContainer<LiveNoteWithAuthor> = try await server.client.list(
            collection: notes, query: PocketQuery(sort: "score", filter: filter)
        )
        #expect(filtered.items.map(\.score) == [4])

        // expand
        let expanded: PocketListContainer<LiveNoteWithAuthor> = try await server.client.list(
            collection: notes, query: PocketQuery(perPage: 1, sort: "score", expand: "author")
        )
        #expect(expanded.items.first?.expand?.author == LiveAuthor(id: ada.id, name: "Ada"))

        // skipTotal: PocketBase answers -1, and the container carries it faithfully
        let skipped: PocketListContainer<LiveNoteWithAuthor> = try await server.client.list(
            collection: notes, query: PocketQuery(perPage: 2, skipTotal: true)
        )
        #expect(skipped.totalItems == -1)
        #expect(skipped.totalPages == -1)
        #expect(skipped.count == 2)

        // view with fields
        struct OnlyTitle: Decodable, Sendable { let title: String }
        let first = try #require(expanded.items.first)
        let narrow: OnlyTitle = try await server.client.view(collection: notes, id: first.id, fields: "title")
        #expect(narrow.title == "note 1")
    }

    @Test("test_live_filterLiteral_stopsAnInjection_thatRawInterpolationSuffers")
    func test_live_filterLiteral_stopsAnInjection_thatRawInterpolationSuffers() async throws {
        let server = try await LiveServer.connect()
        let name = "netkit_notes_\(LiveServer.suffix())"
        try await server.createCollection(.notes(name: name))
        for title in ["it's", "plain", "other"] {
            let _: LiveNote = try await server.client.create(collection: name, record: LiveNoteDraft(title: title, done: false, score: 0, due: nil))
        }

        // A value with a quote is matched exactly.
        let quoted: PocketListContainer<LiveNote> = try await server.client.list(
            collection: name, query: PocketQuery(filter: "title = \(try PocketFilter.literal("it's"))")
        )
        #expect(quoted.items.map(\.title) == ["it's"])

        // The injection payload is just a value that matches nothing.
        let hostile = "zzz' || title != '"
        let safe: PocketListContainer<LiveNote> = try await server.client.list(
            collection: name, query: PocketQuery(filter: "title = \(try PocketFilter.literal(hostile))")
        )
        #expect(safe.items.isEmpty)

        // The same value interpolated raw breaks out of the literal and matches every row.
        let unsafe: PocketListContainer<LiveNote> = try await server.client.list(
            collection: name, query: PocketQuery(filter: "title = '\(hostile)'")
        )
        #expect(unsafe.items.count == 3, "raw interpolation is a filter injection; this is why PocketFilter.literal exists")
    }

    @Test("test_live_dates_roundTripThroughTheFleetFormat")
    func test_live_dates_roundTripThroughTheFleetFormat() async throws {
        let server = try await LiveServer.connect()
        let name = "netkit_notes_\(LiveServer.suffix())"
        try await server.createCollection(.notes(name: name))
        let due = Date(timeIntervalSince1970: 1_712_238_474.692)

        let created: LiveNote = try await server.client.create(
            collection: name, record: LiveNoteDraft(title: "dated", done: false, score: 0, due: due)
        )
        let sent = try #require(created.due)
        #expect(abs(sent.timeIntervalSince(due)) < 0.001)

        let viewed: LiveNote = try await server.client.view(collection: name, id: created.id)
        #expect(viewed.due == created.due)
    }

    @Test("test_live_unsetDate_isTheEmptyString_thatOnlyDecodePocketDateIfPresentReads")
    func test_live_unsetDate_isTheEmptyString_thatOnlyDecodePocketDateIfPresentReads() async throws {
        let server = try await LiveServer.connect()
        let name = "netkit_notes_\(LiveServer.suffix())"
        try await server.createCollection(.notes(name: name))
        struct RawDue: Decodable, Sendable {
            let id: String
            let due: String
        }
        let created: RawDue = try await server.client.create(collection: name, payload: PocketPayload(fields: ["title": .string("undated")]))
        #expect(created.due.isEmpty, "PocketBase serialises an unset date as an empty string, not null")

        // The helper reads it as nil.
        let viewed: LiveNote = try await server.client.view(collection: name, id: created.id)
        #expect(viewed.due == nil)

        // The naive `Date?` property cannot: the documented caveat, pinned against the real server.
        let error = await thrownError { () async throws(PocketError) -> NaiveLiveNote in
            try await server.client.view(collection: name, id: created.id)
        }
        guard case .decoding(let inner, _)? = error, case .dataCorrupted = inner else {
            Issue.record("expected .decoding(dataCorrupted), got \(String(describing: error))"); return
        }
    }

    // MARK: Authentication

    @Test("test_live_auth_registerLoginRefresh_andTheTokenOpensAProtectedWrite")
    func test_live_auth_registerLoginRefresh_andTheTokenOpensAProtectedWrite() async throws {
        let server = try await LiveServer.connect()
        let suffix = LiveServer.suffix()
        let protected = "netkit_private_\(suffix)"
        try await server.createCollection(.notes(name: protected, writeRule: "@request.auth.id != ''"))

        // register = create on the auth collection
        let email = "ada-\(suffix)@netkit-live.test"
        let password = "pw-\(UUID().uuidString)"
        let account: LiveRegistered = try await server.client.create(
            collection: "users", record: LiveAccountDraft(email: email, password: password, passwordConfirm: password)
        )
        #expect(account.id.count == 15)
        #expect(!account.verified)

        // anonymous write is refused by the collection rule, with PocketBase's own message
        let draft = LiveNoteDraft(title: "private", done: false, score: 1, due: nil)
        let anonymous = await thrownError { () async throws(PocketError) -> LiveNote in
            try await server.client.create(collection: protected, record: draft)
        }
        guard case .http(let refusal)? = anonymous else { Issue.record("expected .http, got \(String(describing: anonymous))"); return }
        #expect(refusal.status == 400)
        #expect(refusal.body?.message == "Failed to create record.")

        // login
        let session: PocketAuthResponse<Account> = try await server.client.authWithPassword(
            collection: "users", identity: email, password: password
        )
        #expect(!session.token.isEmpty)
        #expect(session.record.id == account.id)
        #expect(session.record.email == email)

        // the token opens the write
        let written: LiveNote = try await server.client.create(collection: protected, record: draft, token: session.token)
        #expect(written.title == "private")

        // refresh returns the same account with a token the server accepts
        let refreshed: PocketAuthResponse<Account> = try await server.client.authRefresh(collection: "users", token: session.token)
        #expect(refreshed.record.id == account.id)
        let again: LiveNote = try await server.client.create(collection: protected, record: draft, token: refreshed.token)
        #expect(again.id != written.id)
    }

    @Test("test_live_auth_wrongPassword_isAnAuthenticationFailure_withTheServersMessage")
    func test_live_auth_wrongPassword_isAnAuthenticationFailure_withTheServersMessage() async throws {
        let server = try await LiveServer.connect()
        let email = "ada-\(LiveServer.suffix())@netkit-live.test"
        let password = "pw-\(UUID().uuidString)"
        let _: LiveRegistered = try await server.client.create(
            collection: "users", record: LiveAccountDraft(email: email, password: password, passwordConfirm: password)
        )

        let error = await thrownError { () async throws(PocketError) -> PocketAuthResponse<Account> in
            try await server.client.authWithPassword(collection: "users", identity: email, password: "definitely-not-the-password")
        }
        guard case .authentication(let failure)? = error else { Issue.record("expected .authentication, got \(String(describing: error))"); return }
        #expect(failure.status == 400)
        #expect(failure.body?.message == "Failed to authenticate.")
        #expect(failure.endpoint == "POST /api/collections/users/auth-with-password")
    }

    @Test("test_live_auth_refreshWithAGarbageToken_isA401")
    func test_live_auth_refreshWithAGarbageToken_isA401() async throws {
        let server = try await LiveServer.connect()
        let error = await thrownError { () async throws(PocketError) -> PocketAuthResponse<Account> in
            try await server.client.authRefresh(collection: "users", token: "garbage.token.value")
        }
        guard case .authentication(let failure)? = error else { Issue.record("expected .authentication, got \(String(describing: error))"); return }
        #expect(failure.status == 401)
        #expect(failure.body?.message == "The request requires valid record authorization token.")
    }

    @Test("test_live_passwordReset_requestIs204_andConfirmWithABogusTokenIsAValidationFailure")
    func test_live_passwordReset_requestIs204_andConfirmWithABogusTokenIsAValidationFailure() async throws {
        let server = try await LiveServer.connect()
        let email = "ada-\(LiveServer.suffix())@netkit-live.test"
        let password = "pw-\(UUID().uuidString)"
        let _: LiveRegistered = try await server.client.create(
            collection: "users", record: LiveAccountDraft(email: email, password: password, passwordConfirm: password)
        )

        // 204, even for an address that does not exist (PocketBase does not reveal accounts)
        try await server.client.requestPasswordReset(collection: "users", email: email)
        try await server.client.requestPasswordReset(collection: "users", email: "nobody-\(LiveServer.suffix())@netkit-live.test")

        let error = await thrownError { () async throws(PocketError) in
            try await server.client.confirmPasswordReset(
                collection: "users", resetToken: "bogus", password: "another-long-password", passwordConfirm: "another-long-password"
            )
        }
        guard case .http(let failure)? = error else { Issue.record("expected .http, got \(String(describing: error))"); return }
        #expect(failure.status == 400)
        #expect(failure.body?.data["token"]?.code == "validation_invalid_token")
    }

    // MARK: Error bodies

    @Test("test_live_validationFailure_carriesTheFieldErrors")
    func test_live_validationFailure_carriesTheFieldErrors() async throws {
        let server = try await LiveServer.connect()
        let name = "netkit_notes_\(LiveServer.suffix())"
        try await server.createCollection(.notes(name: name))
        let error = await thrownError { () async throws(PocketError) -> LiveNote in
            try await server.client.create(collection: name, payload: PocketPayload(fields: ["done": .bool(true)]))
        }
        guard case .http(let failure)? = error else { Issue.record("expected .http, got \(String(describing: error))"); return }
        #expect(failure.status == 400)
        #expect(failure.body?.message == "Failed to create record.")
        #expect(failure.body?.data["title"] == PocketErrorBody.FieldError(code: "validation_required", message: "Cannot be blank."))
    }

    @Test("test_live_unknownCollection_isA404WithTheServersBody")
    func test_live_unknownCollection_isA404WithTheServersBody() async throws {
        let server = try await LiveServer.connect()
        let error = await thrownError { () async throws(PocketError) -> PocketListContainer<LiveNote> in
            try await server.client.list(collection: "netkit_no_such_\(LiveServer.suffix())")
        }
        guard case .http(let failure)? = error else { Issue.record("expected .http, got \(String(describing: error))"); return }
        #expect(failure.status == 404)
        #expect(failure.body?.message == "Missing collection context.")
    }

    @Test("test_live_unusableFilter_isA400WithTheServersBody")
    func test_live_unusableFilter_isA400WithTheServersBody() async throws {
        let server = try await LiveServer.connect()
        let name = "netkit_notes_\(LiveServer.suffix())"
        try await server.createCollection(.notes(name: name))
        let error = await thrownError { () async throws(PocketError) -> PocketListContainer<LiveNote> in
            try await server.client.list(collection: name, query: PocketQuery(filter: "no_such_field = 1"))
        }
        guard case .http(let failure)? = error else { Issue.record("expected .http, got \(String(describing: error))"); return }
        #expect(failure.status == 400)
        #expect(failure.body != nil)
    }

    @Test("test_live_connectionRefused_isATransportError")
    func test_live_connectionRefused_isATransportError() async throws {
        // Port 1 is reserved and nothing listens there.
        let config = try PocketConfig(endpoint: URL(string: "http://127.0.0.1:1")!, allowInsecureHTTP: true)
        let client = PocketClient(config: config)
        let error = await thrownError { () async throws(PocketError) -> PocketListContainer<LiveNote> in try await client.list(collection: "notes") }
        guard case .transport(let underlying)? = error else { Issue.record("expected .transport, got \(String(describing: error))"); return }
        #expect((underlying as? URLError)?.code == .cannotConnectToHost)
    }

    // MARK: A custom route

    @Test("test_live_route_readsAnArbitraryApiPath")
    func test_live_route_readsAnArbitraryApiPath() async throws {
        let server = try await LiveServer.connect()
        let health: LiveHealth = try await server.client.route("health")
        #expect(health.code == 200)
        #expect(!health.message.isEmpty)
    }

    // MARK: Parity facts measured on the real server

    private struct LegacyLogin: EndPoint {
        let host: String
        let port: Int?
        let identity: String
        let password: String

        var scheme: String { "http" }
        var apiPath: String { "/api/" }
        var path: String { "collections/users/auth-with-password" }
        var method: RequestMethod { .POST }
        // The legacy shape: `accept` only. No Content-Type.
        var header: [String: String]? { ["accept": "application/json"] }
        var body: [String: Any]? { ["identity": identity, "password": password] }
        var queryParams: [String: Any]? { nil }
    }

    @Test("test_live_parity_theLegacyLoginShapeIsRejected_theClientsIsAccepted")
    func test_live_parity_theLegacyLoginShapeIsRejected_theClientsIsAccepted() async throws {
        let server = try await LiveServer.connect()
        let email = "ada-\(LiveServer.suffix())@netkit-live.test"
        let password = "pw-\(UUID().uuidString)"
        let _: LiveRegistered = try await server.client.create(
            collection: "users", record: LiveAccountDraft(email: email, password: password, passwordConfirm: password)
        )

        // Through the shared NetworkProtocol with the legacy endpoint shape (no Content-Type):
        // URLSession labels the body form-urlencoded, and PocketBase cannot read the identity.
        let legacy = LegacyLogin(host: "127.0.0.1", port: server.config.port, identity: email, password: password)
        do {
            let _: PocketAuthResponse<Account> = try await NetworkService().sendRequest(endpoint: legacy)
            Issue.record("expected the legacy shape to be rejected")
        } catch NetworkError.unexpectedStatusCode(let status, _) {
            #expect(status == 400)
        }

        // The same credentials through PocketEndPoint's own labelling succeed.
        let accepted: PocketAuthResponse<Account> = try await server.client.authWithPassword(
            collection: "users", identity: email, password: password
        )
        #expect(accepted.record.email == email)

        // And PocketEndPoint stays usable through the shared NetworkProtocol too.
        let viaLegacyTransport: PocketAuthResponse<Account> = try await NetworkService().sendRequest(
            endpoint: PocketEndPoint.authWithPassword(config: server.config, collection: "users", identity: email, password: password)
        )
        #expect(viaLegacyTransport.record.id == accepted.record.id)
    }

    @Test("test_live_parity_putOnARecordIsNotARoute_patchIs")
    func test_live_parity_putOnARecordIsNotARoute_patchIs() async throws {
        let server = try await LiveServer.connect()
        let name = "netkit_notes_\(LiveServer.suffix())"
        try await server.createCollection(.notes(name: name))
        let created: LiveNote = try await server.client.create(collection: name, record: LiveNoteDraft(title: "t", done: false, score: 0, due: nil))
        let path = "/api/collections/\(name)/records/\(created.id)"
        let body = Data(#"{"done":true}"#.utf8)

        // The legacy markMessageRead verb.
        let put = try await server.raw("PUT", path, body: body)
        #expect(put.status == 404)

        let patched: LiveNote = try await server.client.update(collection: name, id: created.id, payload: PocketPayload(fields: ["done": .bool(true)]))
        #expect(patched.done)
    }

    // MARK: The server really received the calls

    @Test("test_live_serverLog_showsEveryCallTheClientMade")
    func test_live_serverLog_showsEveryCallTheClientMade() async throws {
        let server = try await LiveServer.connect()
        let suffix = LiveServer.suffix()
        let name = "netkit_logged_\(suffix)"
        try await server.createCollection(.notes(name: name))

        let created: LiveNote = try await server.client.create(collection: name, record: LiveNoteDraft(title: "logged", done: false, score: 1, due: nil))
        let _: PocketListContainer<LiveNote> = try await server.client.list(collection: name, query: PocketQuery(perPage: 5))
        let _: LiveNote = try await server.client.view(collection: name, id: created.id)
        let _: LiveNote = try await server.client.update(collection: name, id: created.id, payload: PocketPayload(fields: ["done": .bool(true)]))
        try await server.client.delete(collection: name, id: created.id)
        let missing = await thrownError { () async throws(PocketError) -> LiveNote in try await server.client.view(collection: name, id: created.id) }
        guard case .http? = missing else { Issue.record("expected the deleted record to be gone"); return }

        // Independent of the client: the server's own records API agrees the record is gone,
        // and its collection endpoint lists the collection the test created.
        let gone = try await server.raw("GET", "/api/collections/\(name)/records/\(created.id)")
        #expect(gone.status == 404)
        let listing = try await server.raw("GET", "/api/collections/\(name)/records")
        #expect(listing.status == 200)

        // PocketBase batches its request log (about every 3 seconds): poll, bounded.
        let base = "/api/collections/\(name)/records"
        let expected = [
            ExpectedCall(method: "POST", urlPrefix: base, status: 200),
            ExpectedCall(method: "GET", urlPrefix: base, status: 200),
            ExpectedCall(method: "GET", urlPrefix: "\(base)/\(created.id)", status: 200),
            ExpectedCall(method: "PATCH", urlPrefix: "\(base)/\(created.id)", status: 200),
            ExpectedCall(method: "DELETE", urlPrefix: "\(base)/\(created.id)", status: 204),
            ExpectedCall(method: "GET", urlPrefix: "\(base)/\(created.id)", status: 404),
        ]
        var rows: [LiveLogRow] = []
        var missingCalls: [String] = []
        for _ in 0..<40 {
            rows = try await server.logRows(containing: name)
            missingCalls = expected.filter { call in
                !rows.contains { $0.method == call.method && $0.url?.hasPrefix(call.urlPrefix) == true && $0.status == call.status }
            }.map { "\($0.method) \($0.urlPrefix) -> \($0.status)" }
            if missingCalls.isEmpty { break }
            try await Task.sleep(for: .milliseconds(500))
        }
        #expect(missingCalls.isEmpty, "the server's request log has no row for: \(missingCalls)")
        #expect(rows.count >= expected.count)
    }
}

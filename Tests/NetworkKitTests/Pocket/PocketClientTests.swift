//
//  PocketClientTests.swift
//  NetworkKitTests
//
//  Every PocketClient call and every error path, over a stubbed transport.
//  Nothing in this file touches a network.
//

import Foundation
import Testing
@testable import NetKit

/// A model whose own decoder throws something that is not a `DecodingError`.
private struct Picky: Decodable, Sendable {
    struct Refusal: Error {}
    init(from decoder: any Decoder) throws { throw Refusal() }
}

@Suite("PocketClient — every call over a stubbed transport")
struct PocketClientTests {

    private func makeSUT(
        _ replies: MockPocketTransport.Reply...,
        authorization: String? = nil
    ) throws -> (client: PocketClient, transport: MockPocketTransport) {
        let transport = MockPocketTransport(replies: replies)
        let client = PocketClient(config: try PocketFixtures.config(authorization: authorization), transport: transport)
        return (client, transport)
    }

    // MARK: Records

    @Test("test_list_decodesTheContainer_andSendsTheQueryAndToken")
    func test_list_decodesTheContainer_andSendsTheQueryAndToken() async throws {
        let (client, transport) = try makeSUT(.json(PocketFixtures.listJSON([PocketFixtures.noteJSON()])))
        let page: PocketListContainer<Note> = try await client.list(
            collection: "notes", query: PocketQuery(perPage: 1, filter: "done = false"), token: PocketFixtures.token
        )
        #expect(page.items.map(\.id) == ["rec000000000001"])
        #expect(page.totalItems == 1)

        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/api/collections/notes/records")
        #expect(request.url?.query == "perPage=1&filter=done%20%3D%20false")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(PocketFixtures.token)")
    }

    @Test("test_list_defaults_askForNothingExtra")
    func test_list_defaults_askForNothingExtra() async throws {
        let (client, transport) = try makeSUT(.json(PocketFixtures.listJSON([])))
        let page: PocketListContainer<Note> = try await client.list(collection: "notes")
        #expect(page.isEmpty)
        let request = try #require(await transport.requests.first)
        #expect(request.url?.query == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("test_view_decodesOneRecord")
    func test_view_decodesOneRecord() async throws {
        let (client, transport) = try makeSUT(.json(PocketFixtures.noteJSON(title: "viewed")))
        let note: Note = try await client.view(collection: "notes", id: "rec000000000001", expand: "author")
        #expect(note.title == "viewed")
        let request = try #require(await transport.requests.first)
        #expect(request.url?.path == "/api/collections/notes/records/rec000000000001")
        #expect(request.url?.query == "expand=author")
    }

    @Test("test_create_withAPayload_postsItAndDecodesTheStoredRecord")
    func test_create_withAPayload_postsItAndDecodesTheStoredRecord() async throws {
        let (client, transport) = try makeSUT(.json(PocketFixtures.noteJSON(title: "made")))
        let payload = try PocketPayload(NewNote(title: "made", done: false, score: 1))
        let note: Note = try await client.create(collection: "notes", payload: payload, token: PocketFixtures.token)
        #expect(note.title == "made")
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(try decodeBody(NewNote.self, of: request) == NewNote(title: "made", done: false, score: 1))
    }

    @Test("test_create_withACodableRecord_isTheSameCall")
    func test_create_withACodableRecord_isTheSameCall() async throws {
        let (client, transport) = try makeSUT(.json(PocketFixtures.noteJSON()))
        let note: Note = try await client.create(collection: "notes", record: NewNote(title: "x", done: true, score: 2))
        #expect(note.id == "rec000000000001")
        let request = try #require(await transport.requests.first)
        #expect(try decodeBody(NewNote.self, of: request) == NewNote(title: "x", done: true, score: 2))
    }

    @Test("test_update_isAPatch_andDecodesTheStoredRecord")
    func test_update_isAPatch_andDecodesTheStoredRecord() async throws {
        let (client, transport) = try makeSUT(.json(PocketFixtures.noteJSON(done: true)))
        let note: Note = try await client.update(
            collection: "notes", id: "rec000000000001", record: NewNote(title: "first", done: true, score: 1), token: PocketFixtures.token
        )
        #expect(note.done)
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.path == "/api/collections/notes/records/rec000000000001")
    }

    @Test("test_update_withAPayload_sendsOnlyThoseFields")
    func test_update_withAPayload_sendsOnlyThoseFields() async throws {
        struct Patch: Decodable, Equatable { let done: Bool }
        let (client, transport) = try makeSUT(.json(PocketFixtures.noteJSON(done: true)))
        let _: Note = try await client.update(
            collection: "notes", id: "rec000000000001", payload: PocketPayload(fields: ["done": .bool(true)]), token: nil
        )
        let request = try #require(await transport.requests.first)
        #expect(try decodeBody(Patch.self, of: request) == Patch(done: true))
        #expect(try utf8Text(#require(request.httpBody)) == #"{"done":true}"#)
    }

    @Test("test_delete_accepts204_andAnyEmptyBody")
    func test_delete_accepts204_andAnyEmptyBody() async throws {
        let (client, transport) = try makeSUT(.empty(), .json(status: 200, "{}"))
        try await client.delete(collection: "notes", id: "rec000000000001", token: PocketFixtures.token)
        try await client.delete(collection: "notes", id: "rec000000000002")
        let requests = await transport.requests
        #expect(requests.map(\.httpMethod) == ["DELETE", "DELETE"])
        #expect(requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer \(PocketFixtures.token)")
    }

    // MARK: Authentication

    @Test("test_authWithPassword_returnsTheTokenAndTheRecord")
    func test_authWithPassword_returnsTheTokenAndTheRecord() async throws {
        let (client, transport) = try makeSUT(.json(PocketFixtures.authJSON()))
        let session: PocketAuthResponse<Account> = try await client.authWithPassword(
            collection: "users", identity: "ada@example.test", password: "pw-123456"
        )
        #expect(session.token == PocketFixtures.token)
        #expect(session.record.email == "ada@example.test")
        let request = try #require(await transport.requests.first)
        #expect(request.url?.path == "/api/collections/users/auth-with-password")
        #expect(request.httpMethod == "POST")
    }

    @Test("test_authRefresh_sendsTheTokenAndReturnsAFreshOne")
    func test_authRefresh_sendsTheTokenAndReturnsAFreshOne() async throws {
        let fresh = PocketFixtures.token + "x"
        let (client, transport) = try makeSUT(.json(PocketFixtures.authJSON(token: fresh)))
        let session: PocketAuthResponse<Account> = try await client.authRefresh(collection: "users", token: PocketFixtures.token)
        #expect(session.token == fresh)
        let request = try #require(await transport.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(PocketFixtures.token)")
        #expect(request.url?.path == "/api/collections/users/auth-refresh")
    }

    @Test("test_requestPasswordReset_accepts204")
    func test_requestPasswordReset_accepts204() async throws {
        let (client, transport) = try makeSUT(.empty())
        try await client.requestPasswordReset(collection: "users", email: "ada@example.test")
        let request = try #require(await transport.requests.first)
        #expect(request.url?.path == "/api/collections/users/request-password-reset")
    }

    @Test("test_confirmPasswordReset_accepts204")
    func test_confirmPasswordReset_accepts204() async throws {
        let (client, transport) = try makeSUT(.empty())
        try await client.confirmPasswordReset(
            collection: "users", resetToken: "reset-token", password: "new-password-1", passwordConfirm: "new-password-1"
        )
        let request = try #require(await transport.requests.first)
        #expect(request.url?.path == "/api/collections/users/confirm-password-reset")
    }

    // MARK: Custom routes

    @Test("test_route_decodesAnArbitraryShape")
    func test_route_decodesAnArbitraryShape() async throws {
        struct Boot: Decodable, Sendable, Equatable { let ready: Bool }
        let (client, transport) = try makeSUT(.json(#"{"ready":true}"#))
        let boot: Boot = try await client.route("custom/boot", query: ["env": "prod"], token: PocketFixtures.token)
        #expect(boot == Boot(ready: true))
        let request = try #require(await transport.requests.first)
        #expect(request.url?.absoluteString == "https://pocket.example.test/api/custom/boot?env=prod")
    }

    @Test("test_configCredential_isUsedWhenTheCallCarriesNoToken")
    func test_configCredential_isUsedWhenTheCallCarriesNoToken() async throws {
        let (client, transport) = try makeSUT(.json(PocketFixtures.listJSON([])), authorization: "static-credential")
        let _: PocketListContainer<Note> = try await client.list(collection: "notes")
        let request = try #require(await transport.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "static-credential")
    }

    @Test("test_clientIsUsableThroughItsProtocol")
    func test_clientIsUsableThroughItsProtocol() async throws {
        let (client, _) = try makeSUT(.json(PocketFixtures.listJSON([PocketFixtures.noteJSON()])))
        let boxed: any PocketClientProtocol = client
        let page: PocketListContainer<Note> = try await boxed.list(collection: "notes", query: PocketQuery(), token: nil)
        #expect(page.count == 1)
    }
}

@Suite("PocketClient — every error path keeps what the server said")
struct PocketClientErrorTests {

    private func makeSUT(_ replies: MockPocketTransport.Reply...) throws -> (client: PocketClient, transport: MockPocketTransport) {
        let transport = MockPocketTransport(replies: replies)
        return (PocketClient(config: try PocketFixtures.config(), transport: transport), transport)
    }

    private func list(_ client: PocketClient) async -> PocketError? {
        await thrownError { () async throws(PocketError) -> PocketListContainer<Note> in try await client.list(collection: "notes") }
    }

    // MARK: HTTP failures carry PocketBase's own body

    @Test("test_http400_validation_carriesTheFieldErrors")
    func test_http400_validation_carriesTheFieldErrors() async throws {
        let (client, _) = try makeSUT(.json(status: 400, PocketFixtures.validationJSON))
        let error = await thrownError { () async throws(PocketError) -> Note in
            try await client.create(collection: "notes", payload: PocketPayload(fields: [:]), token: nil)
        }
        guard case .http(let failure)? = error else { Issue.record("expected .http, got \(String(describing: error))"); return }
        #expect(failure.status == 400)
        #expect(failure.endpoint == "POST /api/collections/notes/records")
        #expect(failure.body?.message == "Failed to create record.")
        #expect(failure.body?.data["title"]?.code == "validation_required")
        #expect(try utf8Text(failure.rawBody) == PocketFixtures.validationJSON)
        #expect(error?.body == failure.body)
    }

    @Test("test_http404_carriesTheNotFoundBody")
    func test_http404_carriesTheNotFoundBody() async throws {
        let (client, _) = try makeSUT(.json(status: 404, PocketFixtures.notFoundJSON))
        let error = await thrownError { () async throws(PocketError) -> Note in
            try await client.view(collection: "notes", id: "missing000000000")
        }
        guard case .http(let failure)? = error else { Issue.record("expected .http, got \(String(describing: error))"); return }
        #expect(failure.status == 404)
        #expect(failure.body?.message == "The requested resource wasn't found.")
        #expect(failure.endpoint == "GET /api/collections/notes/records/missing000000000")
    }

    @Test("test_http500_withAnHtmlBody_keepsTheBytes_andNoPocketBaseBody")
    func test_http500_withAnHtmlBody_keepsTheBytes_andNoPocketBaseBody() async throws {
        let html = "<html><body>502 Bad Gateway</body></html>"
        let (client, _) = try makeSUT(.response(status: 502, body: Data(html.utf8)))
        guard case .http(let failure)? = await list(client) else { Issue.record("expected .http"); return }
        #expect(failure.status == 502)
        #expect(failure.body == nil)
        #expect(try utf8Text(failure.rawBody) == html)
    }

    @Test("test_http400_onANonAuthCall_isNotAnAuthenticationFailure")
    func test_http400_onANonAuthCall_isNotAnAuthenticationFailure() async throws {
        let (client, _) = try makeSUT(.json(status: 400, PocketFixtures.validationJSON))
        guard case .http? = await list(client) else { Issue.record("expected .http"); return }
    }

    // MARK: Authentication failures

    @Test("test_loginWithAWrongPassword_isAnAuthenticationFailure_withPocketBasesMessage")
    func test_loginWithAWrongPassword_isAnAuthenticationFailure_withPocketBasesMessage() async throws {
        let (client, _) = try makeSUT(.json(status: 400, PocketFixtures.wrongPasswordJSON))
        let error = await thrownError { () async throws(PocketError) -> PocketAuthResponse<Account> in
            try await client.authWithPassword(collection: "users", identity: "ada@example.test", password: "pw-do-not-leak")
        }
        guard case .authentication(let failure)? = error else { Issue.record("expected .authentication, got \(String(describing: error))"); return }
        #expect(failure.status == 400)
        #expect(failure.body?.message == "Failed to authenticate.")
        let text = error?.description ?? ""
        #expect(text.contains("Failed to authenticate."), "description was: \(text)")
        #expect(!text.contains("pw-do-not-leak"), "description was: \(text)")
    }

    @Test("test_http401_and403_areAuthenticationFailures", arguments: [401, 403])
    func test_http401_and403_areAuthenticationFailures(_ status: Int) async throws {
        let body = #"{"data":{},"message":"The request requires valid record authorization token.","status":\#(status)}"#
        let (client, _) = try makeSUT(.json(status: status, body))
        guard case .authentication(let failure)? = await list(client) else { Issue.record("expected .authentication"); return }
        #expect(failure.status == status)
        #expect(failure.body?.message == "The request requires valid record authorization token.")
    }

    @Test("test_refreshWithAnExpiredToken_isAnAuthenticationFailure")
    func test_refreshWithAnExpiredToken_isAnAuthenticationFailure() async throws {
        let (client, _) = try makeSUT(.json(status: 401, #"{"data":{},"message":"expired","status":401}"#))
        let error = await thrownError { () async throws(PocketError) -> PocketAuthResponse<Account> in
            try await client.authRefresh(collection: "users", token: PocketFixtures.token)
        }
        guard case .authentication? = error else { Issue.record("expected .authentication, got \(String(describing: error))"); return }
    }

    @Test("test_confirmPasswordReset_withABadToken_isAValidationFailure_notAnAuthenticationOne")
    func test_confirmPasswordReset_withABadToken_isAValidationFailure_notAnAuthenticationOne() async throws {
        let body = """
        {"data":{"token":{"code":"validation_invalid_token","message":"Invalid or expired token."}},\
        "message":"An error occurred while validating the submitted data.","status":400}
        """
        let (client, _) = try makeSUT(.json(status: 400, body))
        let error = await thrownError { () async throws(PocketError) in
            try await client.confirmPasswordReset(collection: "users", resetToken: "bogus", password: "new-password-1", passwordConfirm: "new-password-1")
        }
        guard case .http(let failure)? = error else { Issue.record("expected .http, got \(String(describing: error))"); return }
        #expect(failure.body?.data["token"]?.code == "validation_invalid_token")
    }

    // MARK: Transport

    @Test("test_transportFailure_keepsTheUnderlyingError")
    func test_transportFailure_keepsTheUnderlyingError() async throws {
        let (client, _) = try makeSUT(.failure(URLError(.notConnectedToInternet)))
        guard case .transport(let underlying)? = await list(client) else { Issue.record("expected .transport"); return }
        #expect((underlying as? URLError)?.code == .notConnectedToInternet)
    }

    @Test("test_cancellation_isReportedAsCancelled", arguments: [0, 1])
    func test_cancellation_isReportedAsCancelled(_ flavour: Int) async throws {
        let cause: any Error = flavour == 0 ? CancellationError() : URLError(.cancelled)
        let (client, _) = try makeSUT(.failure(cause))
        guard case .cancelled? = await list(client) else { Issue.record("expected .cancelled"); return }
    }

    @Test("test_aNonHTTPResponse_isNamed")
    func test_aNonHTTPResponse_isNamed() async throws {
        let (client, _) = try makeSUT(.nonHTTP)
        guard case .nonHTTPResponse? = await list(client) else { Issue.record("expected .nonHTTPResponse"); return }
    }

    @Test("test_aCallWithNoQueuedReply_failsLoudly_insteadOfInventingA200")
    func test_aCallWithNoQueuedReply_failsLoudly_insteadOfInventingA200() async throws {
        let (client, _) = try makeSUT()
        guard case .transport(let underlying)? = await list(client) else { Issue.record("expected .transport"); return }
        guard case MockPocketTransport.MockError.noReplyQueued? = underlying as? MockPocketTransport.MockError else {
            Issue.record("expected noReplyQueued, got \(underlying)"); return
        }
    }

    // MARK: Decoding

    @Test("test_aSuccessWithAnEmptyBody_whereARecordIsExpected_isEmptyResponse")
    func test_aSuccessWithAnEmptyBody_whereARecordIsExpected_isEmptyResponse() async throws {
        let (client, _) = try makeSUT(.empty(status: 200))
        guard case .emptyResponse(let status)? = await list(client) else { Issue.record("expected .emptyResponse"); return }
        #expect(status == 200)
    }

    @Test("test_aSuccessWithTheWrongShape_isADecodingError_andNeverEchoesTheBody")
    func test_aSuccessWithTheWrongShape_isADecodingError_andNeverEchoesTheBody() async throws {
        // A login answer that lost its record. The body holds the token.
        let (client, _) = try makeSUT(.json(#"{"token":"SECRET-TOKEN-VALUE"}"#))
        let error = await thrownError { () async throws(PocketError) -> PocketAuthResponse<Account> in
            try await client.authWithPassword(collection: "users", identity: "i", password: "p")
        }
        guard case .decoding(_, let status)? = error else { Issue.record("expected .decoding, got \(String(describing: error))"); return }
        #expect(status == 200)
        let text = error?.description ?? ""
        #expect(text.contains("did not decode"), "description was: \(text)")
        #expect(!text.contains("SECRET-TOKEN-VALUE"), "description was: \(text)")
        #expect(!String(describing: error).contains("SECRET-TOKEN-VALUE"))
    }

    @Test("test_anEmptyDateString_isADecodingError_thePocketBaseSerialisationOfAnUnsetDate")
    func test_anEmptyDateString_isADecodingError_thePocketBaseSerialisationOfAnUnsetDate() async throws {
        // PocketBase writes an unset date field as "". The fleet strategy rejects it.
        // This pins the behaviour the PocketClient documentation warns about.
        let json = #"{"id":"rec000000000001","title":"t","done":false,"score":0,"created":""}"#
        let (client, _) = try makeSUT(.json(json))
        let error = await thrownError { () async throws(PocketError) -> Note in
            try await client.view(collection: "notes", id: "rec000000000001")
        }
        guard case .decoding(let inner, _)? = error, case .dataCorrupted = inner else {
            Issue.record("expected .decoding(dataCorrupted), got \(String(describing: error))"); return
        }
    }

    @Test("test_aModelWhoseDecoderThrowsItsOwnError_keepsItAsTheUnderlyingError")
    func test_aModelWhoseDecoderThrowsItsOwnError_keepsItAsTheUnderlyingError() async throws {
        let (client, _) = try makeSUT(.json("{}"))
        let error = await thrownError { () async throws(PocketError) -> Picky in try await client.view(collection: "notes", id: "rec000000000001") }
        guard case .decoding(let inner, _)? = error, case .dataCorrupted(let context) = inner else {
            Issue.record("expected .decoding(dataCorrupted), got \(String(describing: error))"); return
        }
        #expect(context.underlyingError is Picky.Refusal)
    }

    // MARK: Refused before anything is sent

    @Test("test_aBadCollectionName_isRefused_andNothingReachesTheTransport")
    func test_aBadCollectionName_isRefused_andNothingReachesTheTransport() async throws {
        let (client, transport) = try makeSUT(.json(PocketFixtures.listJSON([])))
        let error = await thrownError { () async throws(PocketError) -> PocketListContainer<Note> in try await client.list(collection: "..") }
        guard case .invalidRequest? = error else { Issue.record("expected .invalidRequest, got \(String(describing: error))"); return }
        #expect(await transport.requests.isEmpty)
    }

    @Test("test_aRecordThatCannotBeEncoded_isRefused_andNothingReachesTheTransport")
    func test_aRecordThatCannotBeEncoded_isRefused_andNothingReachesTheTransport() async throws {
        struct Broken: Encodable {
            func encode(to encoder: any Encoder) throws { throw EncodingError.invalidValue(0, .init(codingPath: [], debugDescription: "no")) }
        }
        let (client, transport) = try makeSUT(.json(PocketFixtures.noteJSON()))
        let error = await thrownError { () async throws(PocketError) -> Note in try await client.create(collection: "notes", record: Broken()) }
        guard case .invalidRequest? = error else { Issue.record("expected .invalidRequest, got \(String(describing: error))"); return }
        #expect(await transport.requests.isEmpty)
    }

    // MARK: Descriptions

    @Test("test_everyErrorHasADescription_andNoneContainsACredential")
    func test_everyErrorHasADescription_andNoneContainsACredential() {
        let failure = PocketFailure(endpoint: "GET /api/x", status: 500, body: nil, rawBody: Data())
        let all: [PocketError] = [
            .invalidRequest(reason: "r"), .transport(URLError(.timedOut)), .cancelled, .nonHTTPResponse,
            .authentication(failure), .http(failure), .emptyResponse(status: 200),
            .decoding(.dataCorrupted(.init(codingPath: [], debugDescription: "d")), status: 200),
        ]
        for error in all {
            #expect(!error.description.isEmpty)
            #expect(error.errorDescription == error.description)
            #expect(error.localizedDescription.isEmpty == false)
        }
        #expect(PocketError.cancelled.failure == nil)
        #expect(PocketError.http(failure).failure == failure)
    }
}

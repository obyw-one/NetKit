//
//  UmamiAnswerTests.swift
//  NetKitTests
//
//  The umami answer models the CONTRACT, not the best case.
//
//  Regression: `cache` / `sessionId` / `visitId` were non-optional `String`,
//  so a thin answer to a SUCCESSFUL POST surfaced as `jsonParsingFailed` and
//  the caller recorded a delivered event as failed. Measured cost in shikki:
//  12 telemetry payloads stuck from 2026-10-23 to 2026-10-28, re-failing on
//  every CLI invocation.
//

import Foundation
import Testing

@testable import NetKit

/// `EndPoint` is a protocol, so a test supplies its own conformer — same shape
/// as `MockEndPoint` in `MockNetworkServiceTests`.
private struct SendEndPoint: EndPoint, @unchecked Sendable {
    var host: String = "umami.example.com"
    var path: String = "/api/send"
    var method: RequestMethod = .POST
    var header: [String: String]?
    var body: [String: Any]?
    var queryParams: [String: Any]?
}

@Suite("UmamiAnswer — every shape umami actually returns must decode")
struct UmamiAnswerTests {

    private func decode(_ json: String) throws -> UmamiAnswer {
        try JSONDecoder().decode(UmamiAnswer.self, from: Data(json.utf8))
    }

    @Test("T-UA-01: the full object still decodes — the rich case was never the bug")
    func fullObjectDecodes() throws {
        let a = try decode(#"{"cache":"c1","sessionId":"s1","visitId":"v1"}"#)
        #expect(a.cache == "c1")
        #expect(a.sessionId == "s1")
        #expect(a.visitId == "v1")
    }

    @Test("T-UA-02: an EMPTY object decodes — `{}` is an accepted event, not a parse error")
    func emptyObjectDecodes() throws {
        let a = try decode("{}")
        #expect(a.cache == nil)
        #expect(a.sessionId == nil)
        #expect(a.visitId == nil)
    }

    @Test("T-UA-03: a PARTIAL object decodes — one key present must not reject the rest")
    func partialObjectDecodes() throws {
        let a = try decode(#"{"cache":"only-cache"}"#)
        #expect(a.cache == "only-cache")
        #expect(a.sessionId == nil)
        #expect(a.visitId == nil)
    }

    @Test("T-UA-04: an explicit JSON null decodes as nil, not as a failure")
    func explicitNullDecodes() throws {
        let a = try decode(#"{"cache":null,"sessionId":"s","visitId":null}"#)
        #expect(a.cache == nil)
        #expect(a.sessionId == "s")
        #expect(a.visitId == nil)
    }

    @Test("T-UA-05: a non-JSON body still fails — leniency is about SHAPE, never about validity")
    func bareTokenStillFails() {
        #expect(throws: (any Error).self) { try decode("ok") }
    }

    @Test("T-UA-06: round-trips through encode/decode")
    func roundTrips() throws {
        let original = UmamiAnswer(cache: "c", sessionId: nil, visitId: "v")
        let data = try JSONEncoder().encode(original)
        let back = try JSONDecoder().decode(UmamiAnswer.self, from: data)
        #expect(back == original)
    }

    @Test("T-UA-07: the memberwise init defaults every field, so a caller can build an empty ack")
    func memberwiseDefaults() {
        let a = UmamiAnswer()
        #expect(a.cache == nil)
        #expect(a.sessionId == nil)
        #expect(a.visitId == nil)
    }

    // The end-to-end shape of the original bug: a 2xx whose body is a thin
    // object used to reach the caller as a decode failure. It must now arrive
    // as a value.
    @Test("T-UA-08: a 2xx with a thin body decodes through NetworkProtocol instead of throwing")
    func thinBodyOnSuccessDecodes() async throws {
        let mock = MockNetworkService()
        mock.statusCode = 200
        mock.resultData = Data("{}".utf8)

        let answer: UmamiAnswer = try await mock.sendRequest(endpoint: SendEndPoint())
        #expect(answer.sessionId == nil, "the event was accepted; the body was simply thin")
    }
}

//
//  PocketModelsTests.swift
//  NetworkKitTests
//
//  One Codable per wire shape: the paged-list envelope, the auth envelope,
//  PocketBase's error body, the request payload, the query and the filter.
//

import CoreKit
import Foundation
import Testing
@testable import NetKit

@Suite("PocketListContainer — the paged-list envelope")
struct PocketListContainerTests {

    private func decode(_ json: String) throws -> PocketListContainer<Note> {
        try PocketCodec.decoder().decode(PocketListContainer<Note>.self, from: Data(json.utf8))
    }

    @Test("test_list_decodesTheEnvelopeAndItsRecords")
    func test_list_decodesTheEnvelopeAndItsRecords() throws {
        let json = PocketFixtures.listJSON(
            [PocketFixtures.noteJSON(id: "rec000000000001"), PocketFixtures.noteJSON(id: "rec000000000002", title: "second")],
            page: 2, perPage: 2, totalItems: 5, totalPages: 3
        )
        let container = try decode(json)
        #expect(container.page == 2)
        #expect(container.perPage == 2)
        #expect(container.totalItems == 5)
        #expect(container.totalPages == 3)
        #expect(container.items.map(\.title) == ["first", "second"])
    }

    @Test("test_list_pocketbaseDates_decodeThroughTheFleetStrategy")
    func test_list_pocketbaseDates_decodeThroughTheFleetStrategy() throws {
        let container = try decode(PocketFixtures.listJSON([PocketFixtures.noteJSON()]))
        let created = try #require(container.items.first?.created)
        // 2024-04-04 13:47:54.692Z
        #expect(abs(created.timeIntervalSince1970 - 1_712_238_474.692) < 0.001)
    }

    @Test("test_list_skipTotal_keepsPocketBasesMinusOne")
    func test_list_skipTotal_keepsPocketBasesMinusOne() throws {
        let container = try decode(PocketFixtures.listJSON([], totalItems: -1, totalPages: -1))
        #expect(container.totalItems == -1)
        #expect(container.totalPages == -1)
        #expect(container.isEmpty)
    }

    @Test("test_list_missingEnvelopeKey_isADecodingError")
    func test_list_missingEnvelopeKey_isADecodingError() {
        #expect(throws: DecodingError.self) {
            try decode(#"{"page":1,"perPage":30,"items":[]}"#)
        }
    }

    @Test("test_list_codableRoundTrip_whenTheRecordIsEncodable")
    func test_list_codableRoundTrip_whenTheRecordIsEncodable() throws {
        let original = PocketListContainer<NewNote>(
            page: 1, perPage: 10, totalPages: 1, totalItems: 1, items: [NewNote(title: "a", done: true, score: 2)]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PocketListContainer<NewNote>.self, from: data)
        #expect(decoded == original)
    }

    @Test("test_list_equality_comparesEveryField")
    func test_list_equality_comparesEveryField() {
        let base = PocketListContainer<NewNote>(page: 1, perPage: 10, totalPages: 2, totalItems: 12, items: [])
        let otherPerPage = PocketListContainer<NewNote>(page: 1, perPage: 20, totalPages: 2, totalItems: 12, items: [])
        let otherTotalPages = PocketListContainer<NewNote>(page: 1, perPage: 10, totalPages: 3, totalItems: 12, items: [])
        #expect(base == base)
        #expect(base != otherPerPage)
        #expect(base != otherTotalPages)
        #expect(Set([base, otherPerPage, otherTotalPages]).count == 3)
    }

    @Test("test_list_behavesAsACollectionOverItsItems")
    func test_list_behavesAsACollectionOverItsItems() {
        var container = PocketListContainer<NewNote>(items: [NewNote(title: "a", done: false, score: 1), NewNote(title: "b", done: false, score: 2)])
        #expect(container.count == 2)
        #expect(container.map(\.title) == ["a", "b"])
        #expect(container.reversed().map(\.title) == ["b", "a"])
        #expect(container.last?.title == "b")

        container[0] = NewNote(title: "z", done: true, score: 9)
        #expect(container.items[0].title == "z")

        container.prepend(NewNote(title: "first", done: false, score: 0))
        container.append(NewNote(title: "last", done: false, score: 0))
        #expect(container.map(\.title) == ["first", "z", "b", "last"])
    }

    @Test("test_list_removeFirstAndLast_onAnEmptyPage_returnNilInsteadOfTrapping")
    func test_list_removeFirstAndLast_onAnEmptyPage_returnNilInsteadOfTrapping() {
        var container = PocketListContainer<NewNote>()
        #expect(container.removeFirst() == nil)
        #expect(container.removeLast() == nil)

        container.append(NewNote(title: "only", done: false, score: 1))
        #expect(container.removeLast()?.title == "only")
        #expect(container.isEmpty)
    }
}

@Suite("PocketAuthResponse — the auth envelope")
struct PocketAuthResponseTests {

    @Test("test_auth_decodesTokenAndRecord")
    func test_auth_decodesTokenAndRecord() throws {
        let response = try PocketCodec.decoder().decode(PocketAuthResponse<Account>.self, from: Data(PocketFixtures.authJSON().utf8))
        #expect(response.token == PocketFixtures.token)
        #expect(response.record == Account(id: "user00000000001", email: "ada@example.test", verified: false))
    }

    @Test("test_auth_description_redactsTheToken")
    func test_auth_description_redactsTheToken() {
        let response = PocketAuthResponse(token: PocketFixtures.token, record: Account(id: "u", email: "e@example.test", verified: true))
        for text in [response.description, response.debugDescription, String(describing: response), "\(response)"] {
            #expect(!text.contains(PocketFixtures.token))
            #expect(text.contains("<redacted>"))
        }
    }

    @Test("test_auth_missingRecord_isADecodingError")
    func test_auth_missingRecord_isADecodingError() {
        #expect(throws: DecodingError.self) {
            try PocketCodec.decoder().decode(PocketAuthResponse<Account>.self, from: Data(#"{"token":"t"}"#.utf8))
        }
    }

    @Test("test_auth_codableRoundTrip_whenTheRecordIsEncodable")
    func test_auth_codableRoundTrip_whenTheRecordIsEncodable() throws {
        let original = PocketAuthResponse(token: "t", record: Account(id: "u", email: "e@example.test", verified: false))
        let decoded = try JSONDecoder().decode(PocketAuthResponse<Account>.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }
}

@Suite("PocketErrorBody — the server's own error")
struct PocketErrorBodyTests {

    private func decode(_ json: String) throws -> PocketErrorBody {
        try PocketCodec.decoder().decode(PocketErrorBody.self, from: Data(json.utf8))
    }

    @Test("test_errorBody_decodesFieldFailures")
    func test_errorBody_decodesFieldFailures() throws {
        let body = try decode(PocketFixtures.validationJSON)
        #expect(body.status == 400)
        #expect(body.message == "Failed to create record.")
        #expect(body.data["title"] == PocketErrorBody.FieldError(code: "validation_required", message: "Cannot be blank."))
    }

    @Test("test_errorBody_emptyOrAbsentData_isNoFieldErrors")
    func test_errorBody_emptyOrAbsentData_isNoFieldErrors() throws {
        #expect(try decode(PocketFixtures.notFoundJSON).data.isEmpty)
        #expect(try decode(#"{"status":404,"message":"gone"}"#).data.isEmpty)
    }

    @Test("test_errorBody_notPocketBasesShape_doesNotDecode")
    func test_errorBody_notPocketBasesShape_doesNotDecode() {
        #expect(throws: DecodingError.self) { try decode("<html>502 Bad Gateway</html>") }
        #expect(throws: DecodingError.self) { try decode(#"{"error":"nope"}"#) }
    }

    @Test("test_failure_summary_namesTheCallTheStatusTheMessageAndEachField")
    func test_failure_summary_namesTheCallTheStatusTheMessageAndEachField() throws {
        let failure = PocketFailure(
            endpoint: "POST /api/collections/notes/records", status: 400,
            body: try decode(PocketFixtures.validationJSON), rawBody: Data(PocketFixtures.validationJSON.utf8)
        )
        #expect(failure.summary.contains("POST /api/collections/notes/records"))
        #expect(failure.summary.contains("400"))
        #expect(failure.summary.contains("Failed to create record."))
        #expect(failure.summary.contains("title [validation_required] Cannot be blank."))
    }

    @Test("test_failure_summary_withoutAPocketBaseBody_saysSoAndCountsBytes")
    func test_failure_summary_withoutAPocketBaseBody_saysSoAndCountsBytes() {
        let failure = PocketFailure(endpoint: "GET /api/collections/notes/records", status: 502, body: nil, rawBody: Data("<html>".utf8))
        #expect(failure.summary.contains("502"))
        #expect(failure.summary.contains("not a PocketBase error"))
        #expect(failure.summary.contains("6 bytes"))
    }
}

/// A record whose `encode(to:)` always fails.
private struct Broken: Encodable {
    func encode(to encoder: any Encoder) throws {
        throw EncodingError.invalidValue(0, .init(codingPath: [], debugDescription: "broken on purpose"))
    }
}

/// One record of every JSON shape the payload must keep apart.
private struct Mixed: Encodable {
    let flag: Bool
    let zero: Int
    let one: Int
    let big: Int64
    let ratio: Double
    let name: String
    let nothing: String?
    let tags: [String]
    let nested: MixedNested
    let when: Date
}

private struct MixedNested: Encodable {
    let on: Bool
    let count: Int
}

@Suite("PocketPayload — the typed request body")
struct PocketPayloadTests {

    private func mixed() -> Mixed {
        Mixed(
            flag: true, zero: 0, one: 1, big: 9_007_199_254_740_993, ratio: 1.5, name: "a/b", nothing: nil,
            tags: ["x", "y"], nested: MixedNested(on: false, count: 1), when: Date(timeIntervalSince1970: 1_712_238_474.692)
        )
    }

    @Test("test_payload_keepsBooleansAndNumbersApart")
    func test_payload_keepsBooleansAndNumbersApart() throws {
        let fields = try PocketPayload(mixed()).fields
        #expect(fields["flag"] == .bool(true))
        #expect(fields["zero"] == .integer(0))
        #expect(fields["one"] == .integer(1))
        #expect(fields["nested"] == .object(["on": .bool(false), "count": .integer(1)]))
    }

    @Test("test_payload_keepsLargeIntegersAndFractions")
    func test_payload_keepsLargeIntegersAndFractions() throws {
        let fields = try PocketPayload(mixed()).fields
        #expect(fields["big"] == .integer(9_007_199_254_740_993))
        #expect(fields["ratio"] == .double(1.5))
    }

    @Test("test_payload_stringsArraysAndNil")
    func test_payload_stringsArraysAndNil() throws {
        let fields = try PocketPayload(mixed()).fields
        #expect(fields["name"] == .string("a/b"))
        #expect(fields["tags"] == .array([.string("x"), .string("y")]))
        // An optional left nil is omitted by Codable, not sent as null.
        #expect(fields["nothing"] == nil)
    }

    @Test("test_payload_dates_areWrittenInPocketBasesFormat")
    func test_payload_dates_areWrittenInPocketBasesFormat() throws {
        let fields = try PocketPayload(mixed()).fields
        #expect(fields["when"] == .string("2024-04-04 13:47:54.692Z"))
    }

    @Test("test_payload_jsonData_isSortedAndDoesNotEscapeSlashes")
    func test_payload_jsonData_isSortedAndDoesNotEscapeSlashes() throws {
        let payload = PocketPayload(fields: ["b": .bool(true), "a": .integer(1), "path": .string("x/y")])
        let text = try utf8Text(payload.jsonData())
        #expect(text == #"{"a":1,"b":true,"path":"x/y"}"#)
    }

    @Test("test_payload_aRecordThatIsNotAnObject_isRefused")
    func test_payload_aRecordThatIsNotAnObject_isRefused() {
        #expect(throws: PocketError.self) { try PocketPayload(["a", "b"]) }
        #expect(throws: PocketError.self) { try PocketPayload("just a string") }
    }

    @Test("test_payload_anEncodingFailure_isRefusedNotSwallowed")
    func test_payload_anEncodingFailure_isRefusedNotSwallowed() {
        #expect(throws: PocketError.self) { try PocketPayload(Broken()) }
    }

    @Test("test_payload_nonFiniteNumber_isRefusedAtSerialisation")
    func test_payload_nonFiniteNumber_isRefusedAtSerialisation() {
        #expect(throws: PocketError.self) {
            try PocketPayload(fields: ["x": .double(.infinity)]).jsonData()
        }
    }

    @Test("test_payload_untypedObject_isTheEndPointView")
    func test_payload_untypedObject_isTheEndPointView() {
        let payload = PocketPayload(fields: ["s": .string("v"), "i": .integer(2), "b": .bool(true)])
        let object = payload.untypedObject
        #expect(object["s"] as? String == "v")
        #expect(object["i"] as? Int == 2)
        #expect(object.count == 3)
    }
}

@Suite("PocketQuery and PocketFilter")
struct PocketQueryTests {

    @Test("test_query_default_sendsNothing")
    func test_query_default_sendsNothing() {
        #expect(PocketQuery().items.isEmpty)
    }

    @Test("test_query_items_areInAFixedOrder_andOmitWhatIsAbsent")
    func test_query_items_areInAFixedOrder_andOmitWhatIsAbsent() {
        let query = PocketQuery(page: 3, perPage: 50, sort: "-created", filter: "a = 1", expand: "r", fields: "id", skipTotal: true)
        #expect(query.items.map(\.name) == ["page", "perPage", "sort", "filter", "expand", "fields", "skipTotal"])
        #expect(query.items.map(\.value) == ["3", "50", "-created", "a = 1", "r", "id", "true"])
        #expect(PocketQuery(skipTotal: false).items.isEmpty)
    }

    @Test("test_filterLiteral_quotesAndEscapesTheSingleQuote")
    func test_filterLiteral_quotesAndEscapesTheSingleQuote() throws {
        #expect(try PocketFilter.literal("plain") == "'plain'")
        #expect(try PocketFilter.literal("o'neil") == #"'o\'neil'"#)
        #expect(try PocketFilter.literal("a' || title != '") == #"'a\' || title != \''"#)
        #expect(try PocketFilter.literal("") == "''")
    }

    @Test("test_filterLiteral_aBackslash_isRefused", arguments: [#"a\b"#, #"trail\"#, #"\'"#, #"a\\b"#])
    func test_filterLiteral_aBackslash_isRefused(_ value: String) {
        #expect(throws: PocketError.self) { try PocketFilter.literal(value) }
    }
}

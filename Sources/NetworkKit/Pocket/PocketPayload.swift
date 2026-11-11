//
//  PocketPayload.swift
//  NetworkKit
//
//  The body of a create/update/auth call, as a Sendable JSON object. It is the
//  declared boundary between a typed `Encodable` record and the untyped
//  `[String: Any]` the older `EndPoint` protocol speaks, and it goes through
//  CoreKit's `JSONValue` so nothing `Any` is ever stored.
//

import CoreKit
import Foundation

/// A JSON object destined for a PocketBase request body.
public struct PocketPayload: Equatable, Sendable {

    /// The object's fields.
    public let fields: [String: JSONValue]

    /// A payload from already-typed JSON values (the fixed auth shapes use this).
    public init(fields: [String: JSONValue]) {
        self.fields = fields
    }

    /// A payload from a `Codable` record.
    ///
    /// Dates are written in PocketBase's own format — the symmetric of the
    /// fleet decoder strategy the client reads with.
    ///
    /// - Throws: ``PocketError/invalidRequest(reason:)`` when the record cannot
    ///   be encoded or does not encode to a JSON object (PocketBase records are
    ///   objects).
    public init(_ record: some Encodable) throws(PocketError) {
        let data: Data
        do {
            data = try PocketCodec.encoder().encode(record)
        } catch {
            throw .invalidRequest(reason: "the record could not be encoded: \(error)")
        }
        let node: PocketJSONNode
        do {
            node = try JSONDecoder().decode(PocketJSONNode.self, from: data)
        } catch {
            throw .invalidRequest(reason: "the encoded record is not valid JSON: \(error)")
        }
        guard case .object(let object) = node.value else {
            throw .invalidRequest(reason: "a PocketBase record body must encode to a JSON object")
        }
        fields = object
    }

    /// The `[String: Any]` the `EndPoint` protocol asks for.
    var untypedObject: [String: Any] {
        fields.mapValues(\.untyped)
    }

    /// The request body bytes. Keys are sorted so the same payload is always the
    /// same bytes.
    func jsonData() throws(PocketError) -> Data {
        let object = untypedObject
        guard JSONSerialization.isValidJSONObject(object) else {
            throw .invalidRequest(reason: "the body holds a value JSON cannot represent (NaN or infinity)")
        }
        do {
            return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        } catch {
            throw .invalidRequest(reason: "the body could not be serialised: \(error)")
        }
    }
}

// MARK: - Decoding any JSON into JSONValue

/// `Decodable` mirror of CoreKit's `JSONValue`.
///
/// CoreKit's `JSONValue(untyped:)` is built for a `JSONSerialization` product
/// and tests `as Bool` before `as Int`; on Apple platforms an `NSNumber` 1 or 0
/// passes that test, so `{"n": 1}` would come back `{"n": true}`. Decoding with
/// `JSONDecoder` keeps booleans and numbers apart.
struct PocketJSONNode: Decodable {
    let value: JSONValue

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = .null
        } else if let bool = Self.probe(Bool.self, in: container) {
            value = .bool(bool)
        } else if let integer = Self.probe(Int64.self, in: container) {
            value = .integer(integer)
        } else if let double = Self.probe(Double.self, in: container) {
            value = .double(double)
        } else if let string = Self.probe(String.self, in: container) {
            value = .string(string)
        } else if let array = Self.probe([PocketJSONNode].self, in: container) {
            value = .array(array.map(\.value))
        } else {
            // The last shape: if this is not an object either, the decoder's own error escapes.
            let object = try container.decode([String: PocketJSONNode].self)
            value = .object(object.mapValues(\.value))
        }
    }

    /// Try one JSON shape; `nil` means "the value is not this shape".
    ///
    /// ANY error from a probe means that, not only `DecodingError`: measured on
    /// Apple's Foundation, decoding `1.5` as `Int64` inside a `Decodable` throws
    /// an internal JSON error (which only becomes a `DecodingError` at the outer
    /// `decode` call), so a narrower catch lets a perfectly good fraction
    /// escape. Nothing is hidden by this: when NO shape matches, the final
    /// `container.decode([String: PocketJSONNode].self)` throws the decoder's
    /// own error to the caller.
    private static func probe<Shape: Decodable>(_ shape: Shape.Type, in container: any SingleValueDecodingContainer) -> Shape? {
        do {
            return try container.decode(shape)
        } catch {
            return nil
        }
    }
}

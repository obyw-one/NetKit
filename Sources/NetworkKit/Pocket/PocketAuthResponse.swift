//
//  PocketAuthResponse.swift
//  NetworkKit
//
//  The envelope every PocketBase auth call answers with
//  (`auth-with-password`, `auth-refresh`):
//
//      {"token":"<jwt>","record":{...the auth record...}}
//

import Foundation

/// A PocketBase auth answer: the token and the authenticated record.
///
/// Generic over the record because an auth collection's fields belong to the
/// app that defined it. The description redacts the token, so printing a
/// response (or an error that wraps one) never writes a credential to a log.
public struct PocketAuthResponse<Record: Decodable & Sendable>: Decodable, Sendable {
    public let token: String
    public let record: Record

    public init(token: String, record: Record) {
        self.token = token
        self.record = record
    }
}

extension PocketAuthResponse: Encodable where Record: Encodable {}
extension PocketAuthResponse: Equatable where Record: Equatable {}

extension PocketAuthResponse: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "PocketAuthResponse(token: <redacted>, record: \(record))" }
    public var debugDescription: String { description }
}

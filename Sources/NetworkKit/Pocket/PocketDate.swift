//
//  PocketDate.swift
//  NetworkKit
//
//  Reading a PocketBase date field that may not be set.
//

import Foundation

public extension KeyedDecodingContainer {

    /// A PocketBase date field that may be unset.
    ///
    /// PocketBase serialises a date nobody set as the EMPTY STRING, not as
    /// `null` (measured against 0.25.9 and 0.40.6). The fleet strategy
    /// (`JSONDecoder.pocketbaseDateDecodingStrategy()`) rightly rejects `""` as
    /// a date, so a plain `Date?` property fails to decode the whole record.
    /// This reads absent, `null` and `""` as `nil`, and anything else through the
    /// decoder's own date strategy — a malformed date is still an error.
    ///
    /// ```swift
    /// init(from decoder: any Decoder) throws {
    ///     let container = try decoder.container(keyedBy: CodingKeys.self)
    ///     due = try container.decodePocketDateIfPresent(forKey: .due)
    /// }
    /// ```
    func decodePocketDateIfPresent(forKey key: Key) throws -> Date? {
        guard contains(key), try !decodeNil(forKey: key), !(try decode(String.self, forKey: key)).isEmpty else { return nil }
        return try decode(Date.self, forKey: key)
    }
}

import Foundation

// MARK: - BonjourTXTRecord

/// Utility for parsing and encoding Bonjour TXT record data
/// (length-prefixed key=value pairs as produced by ``NetService``).
///
/// The ``parse(_:)`` / ``encode(_:)`` pair is a round-trip: data encoded with
/// ``encode(_:)`` can be decoded by ``parse(_:)`` and vice-versa.
///
/// - Note: Extracted verbatim from BrainyTubeKit/Services/BonjourBrowser.swift
///   (2026-06-21) and promoted to a standalone NetKit primitive.
public enum BonjourTXTRecord {

    // MARK: - Parsing

    /// Parse raw TXT record ``Data`` into a ``[String: String]`` dictionary.
    ///
    /// The format is a sequence of length-prefixed records where each record
    /// is a UTF-8 string of the form `key=value`. Records that cannot be
    /// decoded as UTF-8 or do not contain `=` are silently skipped.
    ///
    /// - Parameter data: The raw TXT record bytes (as returned by
    ///   ``NetService/txtRecordData()``).
    /// - Returns: A dictionary mapping TXT keys to their string values.
    public static func parse(_ data: Data) -> [String: String] {
        var result: [String: String] = [:]
        var index = data.startIndex

        while index < data.endIndex {
            let length = Int(data[index])
            index = data.index(after: index)

            guard index.advanced(by: length) <= data.endIndex else { break }

            let entryData = data[index..<index.advanced(by: length)]
            if let entry = String(data: entryData, encoding: .utf8),
               let eqIndex = entry.firstIndex(of: "=") {
                let key = String(entry[entry.startIndex..<eqIndex])
                let value = String(entry[entry.index(after: eqIndex)...])
                result[key] = value
            }
            index = index.advanced(by: length)
        }

        return result
    }

    // MARK: - Encoding

    /// Encode a ``[String: String]`` dictionary into the length-prefixed
    /// ``Data`` blob that ``NetService/setTXTRecord(_:)`` expects.
    ///
    /// Uses ``NetService/data(fromTXTRecord:)`` internally so the output is
    /// byte-for-byte identical to what the system would produce.
    ///
    /// - Parameter values: Dictionary of TXT key-value pairs to encode.
    /// - Returns: Encoded TXT record data suitable for ``NetService/setTXTRecord(_:)``.
    public static func encode(_ values: [String: String]) -> Data {
        let bytes: [String: Data] = values.reduce(into: [:]) { acc, pair in
            acc[pair.key] = Data(pair.value.utf8)
        }
        return NetService.data(fromTXTRecord: bytes)
    }
}

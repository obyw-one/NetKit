import Foundation
import Testing

// Bonjour moved to the Apple-only target in the main->develop
// reconciliation: it imports Network and os, which the portable NetKit
// target may not (spec c8fa126c, BR-L-04).
@testable import NetKitApple

// MARK: - BonjourTXTRecordTests

@Suite("BonjourTXTRecord")
struct BonjourTXTRecordTests {

    // MARK: - Parse

    @Test("parse empty data returns empty dictionary")
    func parseEmpty() {
        let result = BonjourTXTRecord.parse(Data())
        #expect(result.isEmpty)
    }

    @Test("parse single key=value entry")
    func parseSingleEntry() {
        // Build raw TXT data: [length][key=value bytes]
        let entry = "version=1"
        let bytes = Array(entry.utf8)
        var data = Data([UInt8(bytes.count)])
        data.append(contentsOf: bytes)

        let result = BonjourTXTRecord.parse(data)
        #expect(result["version"] == "1")
        #expect(result.count == 1)
    }

    @Test("parse multiple key=value entries")
    func parseMultipleEntries() {
        var data = Data()
        for pair in ["key1=alpha", "key2=beta", "key3=gamma"] {
            let bytes = Array(pair.utf8)
            data.append(UInt8(bytes.count))
            data.append(contentsOf: bytes)
        }

        let result = BonjourTXTRecord.parse(data)
        #expect(result["key1"] == "alpha")
        #expect(result["key2"] == "beta")
        #expect(result["key3"] == "gamma")
        #expect(result.count == 3)
    }

    @Test("parse entry with = in value")
    func parseEqualsInValue() {
        let entry = "url=http://host:8080/path?q=1"
        let bytes = Array(entry.utf8)
        var data = Data([UInt8(bytes.count)])
        data.append(contentsOf: bytes)

        let result = BonjourTXTRecord.parse(data)
        #expect(result["url"] == "http://host:8080/path?q=1")
    }

    @Test("parse skips truncated entry")
    func parseTruncated() {
        // Claim 10 bytes but only provide 4
        var data = Data([10])
        data.append(contentsOf: Array("abcd".utf8))

        let result = BonjourTXTRecord.parse(data)
        // Truncated entry is skipped; result may be empty or partial
        // but must not crash.
        #expect(result.isEmpty)
    }

    // MARK: - Encode

    @Test("encode produces non-empty data for non-empty dictionary")
    func encodeNonEmpty() {
        let data = BonjourTXTRecord.encode(["version": "1"])
        #expect(!data.isEmpty)
    }

    @Test("encode empty dictionary produces empty-ish data")
    func encodeEmpty() {
        // NetService.data(fromTXTRecord:[:]) returns Data() or minimal stub.
        let data = BonjourTXTRecord.encode([:])
        // Just verify it doesn't crash.
        #expect(data.isEmpty)
    }

    // MARK: - Round-trip

    @Test("parse(encode(dict)) is identity")
    func roundTrip() {
        let original: [String: String] = [
            "version": "1",
            "node": "primary",
            "region": "eu-west-1",
        ]

        let encoded = BonjourTXTRecord.encode(original)
        let decoded = BonjourTXTRecord.parse(encoded)

        #expect(decoded == original)
    }

    @Test("round-trip preserves values containing special characters")
    func roundTripSpecialChars() {
        let original = ["path": "/api/v2?debug=true&limit=10"]
        let decoded = BonjourTXTRecord.parse(BonjourTXTRecord.encode(original))
        #expect(decoded == original)
    }
}

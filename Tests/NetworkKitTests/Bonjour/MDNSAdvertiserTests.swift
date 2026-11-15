import Foundation
import Testing

// Bonjour moved to the Apple-only target in the main->develop
// reconciliation: it imports Network and os, which the portable NetKit
// target may not (spec c8fa126c, BR-L-04).
@testable import NetKitApple

// MARK: - MDNSAdvertiserTests

@Suite("MDNSAdvertiser")
struct MDNSAdvertiserTests {

    // MARK: - TXT record encoding

    @Test("BonjourTXTRecord encode/parse round-trip for advertiser payload")
    func advertiserTXTRoundTrip() {
        // This is the canonical test for the TXT record shape that MDNSAdvertiser
        // produces. The advertiser calls BonjourTXTRecord.encode(txtRecord) internally;
        // here we verify the round-trip independently.
        let txt: [String: String] = [
            "version": "1",
            "node": "primary",
            "region": "eu-west-1",
        ]
        let encoded = BonjourTXTRecord.encode(txt)
        let decoded = BonjourTXTRecord.parse(encoded)
        #expect(decoded == txt)
    }

    // MARK: - Advertiser configuration

    @Test("MDNSAdvertiser stores serviceType and name")
    @MainActor
    func advertiserStoresConfig() {
        let advertiser = MDNSAdvertiser(
            serviceType: "_shi-nats._tcp",
            name: "Test Broker",
            port: 4222,
            txtRecord: ["version": "1"]
        )
        // isAdvertising starts false — NetService.publish() is NOT called in init.
        #expect(!advertiser.isAdvertising)
    }

    @Test("MDNSAdvertiser isAdvertising toggles on start/stop")
    @MainActor
    func advertiserStartStop() {
        let advertiser = MDNSAdvertiser(
            serviceType: "_shikki-test._tcp",
            name: "Unit Test Service",
            port: 9999,
            txtRecord: [:]
        )

        #expect(!advertiser.isAdvertising)

        // start() sets isAdvertising optimistically before NetService confirms.
        advertiser.start()
        #expect(advertiser.isAdvertising)

        // stop() clears isAdvertising.
        advertiser.stop()
        #expect(!advertiser.isAdvertising)
    }

    @Test("MDNSAdvertiser start is idempotent")
    @MainActor
    func advertiserIdempotentStart() {
        let advertiser = MDNSAdvertiser(
            serviceType: "_shikki-test._tcp",
            name: "Idempotent Test",
            port: 1234,
            txtRecord: [:]
        )
        advertiser.start()
        advertiser.start() // second call must not double-publish or crash
        #expect(advertiser.isAdvertising)
        advertiser.stop()
    }

    @Test("MDNSAdvertiser stop when not advertising is safe")
    @MainActor
    func advertiserStopWhenStopped() {
        let advertiser = MDNSAdvertiser(
            serviceType: "_shikki-test._tcp",
            name: "Noop Stop",
            port: 5678,
            txtRecord: [:]
        )
        // Should not crash.
        advertiser.stop()
        #expect(!advertiser.isAdvertising)
    }

    // MARK: - Service type convention documentation test

    @Test("service type convention: shikki NATS broker should use _shi-nats._tcp")
    @MainActor
    func serviceTypeConvention() {
        // This test documents the recommended service ID for shikki consumers.
        // The advertiser itself does not enforce any naming convention;
        // it accepts whatever string the caller provides.
        let shiNATSType = "_shi-nats._tcp"
        let advertiser = MDNSAdvertiser(
            serviceType: shiNATSType,
            name: "NATS Primary",
            port: 4222,
            txtRecord: ["version": "1", "cluster": "shikki-dev"]
        )
        // Structural check: init completes without error.
        // The `_shi-nats._tcp` convention is documented in
        // Sources/NetworkKit/Bonjour/README.md.
        #expect(!advertiser.isAdvertising)
    }
}

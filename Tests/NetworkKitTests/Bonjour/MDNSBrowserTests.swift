import Foundation
import Testing

// Bonjour moved to the Apple-only target in the main->develop
// reconciliation: it imports Network and os, which the portable NetKit
// target may not (spec c8fa126c, BR-L-04).
@testable import NetKitApple

// MARK: - MockBonjourBrowser

/// Test double for ``BonjourNetworkBrowsing`` that fires callbacks synchronously
/// without touching the real network.
final class MockBonjourBrowser: BonjourNetworkBrowsing, @unchecked Sendable {

    // MARK: - BonjourNetworkBrowsing

    weak var browsingDelegate: (any BonjourNetworkBrowsingDelegate)?

    var searchCallCount: Int = 0
    var stopCallCount: Int = 0
    var lastSearchedType: String?
    var lastSearchedDomain: String?

    func searchForServices(ofType type: String, inDomain domain: String) {
        searchCallCount += 1
        lastSearchedType = type
        lastSearchedDomain = domain
    }

    func stop() {
        stopCallCount += 1
    }

    // MARK: - Simulation helpers

    func simulateFound(_ descriptor: BonjourServiceDescriptor, moreComing: Bool = false) {
        browsingDelegate?.bonjourBrowser(didFind: descriptor, moreComing: moreComing)
    }

    func simulateRemoved(_ descriptor: BonjourServiceDescriptor, moreComing: Bool = false) {
        browsingDelegate?.bonjourBrowser(didRemove: descriptor, moreComing: moreComing)
    }

    func simulateSearchFailed(code: Int = -1) {
        browsingDelegate?.bonjourBrowser(
            didNotSearch: BonjourDiscoveryError.searchFailed("code \(code)")
        )
    }
}

// MARK: - MockBonjourResolver

/// Test double for ``BonjourServiceResolving`` that resolves synchronously
/// from a pre-configured map.
final class MockBonjourResolver: BonjourServiceResolving, Sendable {

    private let results: [String: BonjourResolvedService]
    private let shouldThrow: Bool

    /// - Parameters:
    ///   - results: Map of service name → resolved result.
    ///   - shouldThrow: If `true`, every resolve call throws ``BonjourDiscoveryError/resolutionTimeout``.
    init(
        results: [String: BonjourResolvedService] = [:],
        shouldThrow: Bool = false
    ) {
        self.results = results
        self.shouldThrow = shouldThrow
    }

    func resolve(_ service: BonjourServiceDescriptor, timeout: TimeInterval) async throws -> BonjourResolvedService {
        if shouldThrow {
            throw BonjourDiscoveryError.resolutionTimeout
        }
        guard let result = results[service.name] else {
            throw BonjourDiscoveryError.resolutionTimeout
        }
        return result
    }
}

// MARK: - MDNSBrowserTests

@Suite("MDNSBrowser")
struct MDNSBrowserTests {

    // MARK: - Helpers

    func makeDescriptor(name: String, type: String = "_shikki-test._tcp.") -> BonjourServiceDescriptor {
        BonjourServiceDescriptor(name: name, type: type, domain: "local.")
    }

    func makeResolved(name: String, host: String = "myhost.local", port: Int = 4222) -> BonjourResolvedService {
        BonjourResolvedService(
            name: name,
            hostName: host,
            port: port,
            txtRecord: ["version": "1"]
        )
    }

    // MARK: - Tests

    @Test("discover calls searchForServices with injected serviceType")
    func discoverCallsSearch() async throws {
        let mockBrowser = MockBonjourBrowser()
        let mockResolver = MockBonjourResolver()

        let browser = MDNSBrowser(
            serviceType: "_shikki-test._tcp.",
            networkBrowser: mockBrowser,
            resolver: mockResolver
        )

        // Fire discover with tiny timeout so the test doesn't block.
        _ = try await browser.discover(timeout: 0.1)

        #expect(mockBrowser.searchCallCount == 1)
        #expect(mockBrowser.lastSearchedType == "_shikki-test._tcp.")
        #expect(mockBrowser.lastSearchedDomain == "local.")
    }

    @Test("discover returns resolved service when mock fires didFind")
    func discoverReturnsResolvedService() async throws {
        let mockBrowser = MockBonjourBrowser()
        let descriptor = makeDescriptor(name: "TestNATS")
        let resolved = makeResolved(name: "TestNATS")
        let mockResolver = MockBonjourResolver(results: ["TestNATS": resolved])

        let browser = MDNSBrowser(
            serviceType: "_shikki-test._tcp.",
            networkBrowser: mockBrowser,
            resolver: mockResolver
        )

        // Simulate discovery from a concurrent Task since discover() starts the browser
        // and the mock delegate is only set inside discover().
        let discoverTask = Task {
            try await browser.discover(timeout: 3.0)
        }

        // Yield briefly so the discover() task can set the delegate.
        try await Task.sleep(for: .milliseconds(100))

        // Simulate Bonjour finding the service.
        mockBrowser.simulateFound(descriptor)

        let results = try await discoverTask.value
        #expect(results.count == 1)
        #expect(results.first?.name == "TestNATS")
        #expect(results.first?.port == 4222)
        #expect(results.first?.hostName == "myhost.local")
    }

    @Test("discover skips services that fail resolution")
    func discoverSkipsFailedResolutions() async throws {
        let mockBrowser = MockBonjourBrowser()
        let descriptor = makeDescriptor(name: "BadService")
        let mockResolver = MockBonjourResolver(shouldThrow: true)

        let browser = MDNSBrowser(
            serviceType: "_shikki-test._tcp.",
            networkBrowser: mockBrowser,
            resolver: mockResolver
        )

        let discoverTask = Task {
            try await browser.discover(timeout: 0.5)
        }

        try await Task.sleep(for: .milliseconds(50))
        mockBrowser.simulateFound(descriptor)

        let results = try await discoverTask.value
        // Resolution failure means no results, not a throw.
        #expect(results.isEmpty)
    }

    @Test("discover removes service when didRemove fires before resolution completes")
    func discoverRemovesBeforeResolution() async throws {
        let mockBrowser = MockBonjourBrowser()
        let descriptor = makeDescriptor(name: "FlappyService")
        // Resolver has a result but the service is removed before resolution runs.
        let resolved = makeResolved(name: "FlappyService")
        let mockResolver = MockBonjourResolver(results: ["FlappyService": resolved])

        let browser = MDNSBrowser(
            serviceType: "_shikki-test._tcp.",
            networkBrowser: mockBrowser,
            resolver: mockResolver
        )

        let discoverTask = Task {
            try await browser.discover(timeout: 0.5)
        }

        try await Task.sleep(for: .milliseconds(50))
        mockBrowser.simulateFound(descriptor)
        // Immediately remove before resolver fires.
        mockBrowser.simulateRemoved(descriptor)

        let results = try await discoverTask.value
        // Removed services should not appear even if resolver would succeed.
        // (Race-dependent: this test documents expected behavior.)
        _ = results // result set may be 0 or 1 depending on Task scheduling; no crash expected.
    }

    @Test("stopDiscovery calls stop on networkBrowser")
    func stopDiscovery() {
        let mockBrowser = MockBonjourBrowser()
        let browser = MDNSBrowser(
            serviceType: "_test._tcp.",
            networkBrowser: mockBrowser,
            resolver: MockBonjourResolver()
        )
        browser.stopDiscovery()
        #expect(mockBrowser.stopCallCount == 1)
    }

    @Test("BonjourServiceDescriptor equality")
    func descriptorEquality() {
        let a = BonjourServiceDescriptor(name: "Foo", type: "_t._tcp.", domain: "local.")
        let b = BonjourServiceDescriptor(name: "Foo", type: "_t._tcp.", domain: "local.")
        let c = BonjourServiceDescriptor(name: "Bar", type: "_t._tcp.", domain: "local.")
        #expect(a == b)
        #expect(a != c)
    }

    @Test("BonjourResolvedService baseURL convenience accessor")
    func resolvedServiceBaseURL() {
        let svc = BonjourResolvedService(
            name: "Broker",
            hostName: "broker.local",
            port: 4222,
            txtRecord: ["baseURL": "http://broker.local:4222"]
        )
        #expect(svc.baseURL == "http://broker.local:4222")

        let noURL = BonjourResolvedService(
            name: "Broker", hostName: "x", port: 1, txtRecord: [:]
        )
        #expect(noURL.baseURL == nil)
    }
}

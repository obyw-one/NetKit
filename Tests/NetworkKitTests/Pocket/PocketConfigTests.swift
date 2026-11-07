//
//  PocketConfigTests.swift
//  NetworkKitTests
//
//  PocketConfig is injected and validated at construction. There is no default
//  URL, and a missing or unusable one is a NAMED error.
//

import Foundation
import Testing
@testable import NetKit

@Suite("PocketConfig — injected, validated, no default URL")
struct PocketConfigTests {

    // MARK: Accepts

    @Test("test_config_httpsRoot_isAccepted")
    func test_config_httpsRoot_isAccepted() throws {
        let config = try PocketConfig(endpoint: URL(string: "https://pocket.example.test")!)
        #expect(config.scheme == "https")
        #expect(config.host == "pocket.example.test")
        #expect(config.port == nil)
        #expect(config.authorization == nil)
    }

    @Test("test_config_trailingSlash_isStillTheRoot")
    func test_config_trailingSlash_isStillTheRoot() throws {
        let config = try PocketConfig(endpoint: URL(string: "https://pocket.example.test/")!)
        #expect(config.host == "pocket.example.test")
    }

    @Test("test_config_explicitPort_isKept")
    func test_config_explicitPort_isKept() throws {
        let config = try PocketConfig(endpoint: URL(string: "http://127.0.0.1:8090")!, allowInsecureHTTP: true)
        #expect(config.scheme == "http")
        #expect(config.port == 8090)
    }

    @Test("test_config_schemeIsCaseInsensitive")
    func test_config_schemeIsCaseInsensitive() throws {
        let config = try PocketConfig(endpoint: URL(string: "HTTPS://pocket.example.test")!)
        #expect(config.scheme == "https")
    }

    @Test("test_config_authorization_isKeptVerbatim")
    func test_config_authorization_isKeptVerbatim() throws {
        let config = try PocketConfig(endpoint: URL(string: "https://pocket.example.test")!, authorization: "Bearer abc")
        #expect(config.authorization == "Bearer abc")
    }

    // MARK: Refuses

    @Test("test_config_http_withoutOptIn_isRefused")
    func test_config_http_withoutOptIn_isRefused() {
        #expect(throws: PocketConfigError.insecureHTTPNotAllowed) {
            try PocketConfig(endpoint: URL(string: "http://pocket.example.test")!)
        }
    }

    @Test("test_config_unsupportedScheme_isNamed")
    func test_config_unsupportedScheme_isNamed() {
        #expect(throws: PocketConfigError.unsupportedScheme("ftp")) {
            try PocketConfig(endpoint: URL(string: "ftp://pocket.example.test")!)
        }
    }

    @Test("test_config_noHost_isRefused")
    func test_config_noHost_isRefused() {
        #expect(throws: PocketConfigError.emptyHost) {
            try PocketConfig(endpoint: URL(string: "https:///")!)
        }
    }

    @Test("test_config_pathQueryFragment_areRefused", arguments: [
        "https://pocket.example.test/api",
        "https://pocket.example.test/pb/",
        "https://pocket.example.test?x=1",
        "https://pocket.example.test/#frag",
    ])
    func test_config_pathQueryFragment_areRefused(_ endpoint: String) {
        #expect(throws: PocketConfigError.unexpectedComponents) {
            try PocketConfig(endpoint: URL(string: endpoint)!)
        }
    }

    @Test("test_config_blankAuthorization_isRefused", arguments: ["", "   ", "\n\t"])
    func test_config_blankAuthorization_isRefused(_ authorization: String) {
        #expect(throws: PocketConfigError.blankAuthorization) {
            try PocketConfig(endpoint: URL(string: "https://pocket.example.test")!, authorization: authorization)
        }
    }

    // MARK: A missing config is a named error, never a fallback

    @Test("test_config_nilEndpoint_isMissingEndpoint")
    func test_config_nilEndpoint_isMissingEndpoint() {
        let absent: String? = nil
        #expect(throws: PocketConfigError.missingEndpoint) {
            try PocketConfig(endpoint: absent)
        }
    }

    @Test("test_config_emptyOrWhitespaceEndpoint_isMissingEndpoint", arguments: ["", "   ", "\n"])
    func test_config_emptyOrWhitespaceEndpoint_isMissingEndpoint(_ endpoint: String) {
        #expect(throws: PocketConfigError.missingEndpoint) {
            try PocketConfig(endpoint: endpoint)
        }
    }

    @Test("test_config_stringEndpoint_isParsedAndValidated")
    func test_config_stringEndpoint_isParsedAndValidated() throws {
        let config = try PocketConfig(endpoint: " https://pocket.example.test:8443 ", authorization: "Bearer abc")
        #expect(config.host == "pocket.example.test")
        #expect(config.port == 8443)
        #expect(config.authorization == "Bearer abc")
    }

    @Test("test_config_hostWithoutScheme_isNamed")
    func test_config_hostWithoutScheme_isNamed() {
        // The commonest mistake: `localhost:8090` parses as scheme "localhost".
        #expect(throws: PocketConfigError.unsupportedScheme("localhost")) {
            try PocketConfig(endpoint: "localhost:8090")
        }
        #expect(throws: PocketConfigError.unsupportedScheme(nil)) {
            try PocketConfig(endpoint: "pocket.example.test")
        }
    }

    // MARK: Secrets and echoes

    @Test("test_config_description_redactsTheCredential")
    func test_config_description_redactsTheCredential() throws {
        let secret = "s3cr3t-static-token"
        let config = try PocketConfig(endpoint: URL(string: "https://pocket.example.test")!, authorization: secret)
        #expect(!config.description.contains(secret))
        #expect(!config.debugDescription.contains(secret))
        #expect(!String(describing: config).contains(secret))
        #expect(config.description.contains("<redacted>"))
        #expect(config.description.contains("pocket.example.test"))
    }

    @Test("test_config_errorDescriptions_neverEchoTheOffendingValue")
    func test_config_errorDescriptions_neverEchoTheOffendingValue() {
        let withPath = PocketConfigError.unexpectedComponents.description
        #expect(!withPath.contains("/api"))
        for error in [PocketConfigError.missingEndpoint, .malformedEndpoint, .emptyHost, .insecureHTTPNotAllowed, .blankAuthorization] {
            #expect(!error.description.isEmpty)
        }
    }

    @Test("test_config_equatable")
    func test_config_equatable() throws {
        let one = try PocketConfig(endpoint: URL(string: "https://pocket.example.test")!)
        let same = try PocketConfig(endpoint: URL(string: "https://pocket.example.test/")!)
        let other = try PocketConfig(endpoint: URL(string: "https://other.example.test")!)
        #expect(one == same)
        #expect(one != other)
    }
}

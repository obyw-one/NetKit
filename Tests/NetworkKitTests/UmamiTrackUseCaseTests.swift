//
//  UmamiTrackUseCaseTests.swift
//  NetKitTests
//
//  W1 T-05 — the use case decodes an ``UmamiAnswer`` from a stubbed
//  ``NetworkProtocol`` and maps any ``NetworkError`` to
//  ``TrackUseCaseError/networkError``.
//

import Foundation
import Testing

@testable import NetKit

@Suite("UmamiTrackUseCase")
struct UmamiTrackUseCaseTests {

  private struct StubTrackInfo: TrackInfoProtocol {
    var url: String = "/cli"
    var title: String = "shikki.verb.exit"
    var referrer: String? = nil
    var tag: String? = nil
    var extra: [String: String] = [:]
  }

  private static func makeConfig() throws -> UmamiConfig {
    try UmamiConfig(
      endpoint: URL(string: "https://umami.example")!,
      websiteId: "site-1",
      hostname: "com.example.app"
    )
  }

  // MARK: - T-05

  @Test("T-05 execute returns the decoded UmamiAnswer")
  func t05_returnsDecodedAnswer() async throws {
    let mock = MockNetworkService()
    let answer = UmamiAnswer(cache: "cache-token", sessionId: "sess-1", visitId: "visit-1")
    mock.resultData = try JSONEncoder().encode(answer)

    let useCase = UmamiTrackUseCase(networkService: mock, config: try Self.makeConfig())
    let result = try await useCase.execute(StubTrackInfo())

    #expect(result == answer)
    #expect(mock.capturedRequests.count == 1)
  }

  @Test("T-05 unexpectedStatusCode maps to TrackUseCaseError.networkError")
  func t05_mapsUnexpectedStatusCode() async throws {
    let mock = MockNetworkService()
    mock.resultError = .unexpectedStatusCode(500)

    let useCase = UmamiTrackUseCase(networkService: mock, config: try Self.makeConfig())

    await #expect(throws: TrackUseCaseError.networkError) {
      _ = try await useCase.execute(StubTrackInfo())
    }
  }

  @Test("T-05 requestFailed maps to TrackUseCaseError.networkError")
  func t05_mapsRequestFailed() async throws {
    let mock = MockNetworkService()
    mock.resultError = .requestFailed(description: "offline")

    let useCase = UmamiTrackUseCase(networkService: mock, config: try Self.makeConfig())

    await #expect(throws: TrackUseCaseError.networkError) {
      _ = try await useCase.execute(StubTrackInfo())
    }
  }

  @Test("T-05 invalidData maps to TrackUseCaseError.networkError")
  func t05_mapsInvalidData() async throws {
    let mock = MockNetworkService()
    mock.resultError = .invalidData

    let useCase = UmamiTrackUseCase(networkService: mock, config: try Self.makeConfig())

    await #expect(throws: TrackUseCaseError.networkError) {
      _ = try await useCase.execute(StubTrackInfo())
    }
  }

  @Test("T-05 execute captures the request through the injected NetworkProtocol")
  func t05_requestGoesThroughInjectedService() async throws {
    let mock = MockNetworkService()
    mock.resultData = try JSONEncoder().encode(
      UmamiAnswer(cache: "c", sessionId: "s", visitId: "v")
    )

    let config = try Self.makeConfig()
    let useCase = UmamiTrackUseCase(networkService: mock, config: config)
    _ = try await useCase.execute(
      StubTrackInfo(
        url: "/cli",
        title: "shikki.verb.exit",
        extra: ["shi_version": "0.9.1"]
      )
    )

    let request = try #require(mock.capturedRequests.first)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path == "/api/send")
    #expect(request.url?.host == "umami.example")
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
  }
}

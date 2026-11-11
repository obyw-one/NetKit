//
//  UmamiReadClientTests.swift
//  NetKitTests
//
//  The umami read endpoints. The HTTP layer is stubbed (MockNetworkService);
//  nothing here touches a live umami, and the token is a placeholder literal
//  that no assertion prints.
//

import Foundation
import Testing

@testable import NetKit

@Suite("UmamiReadClient")
struct UmamiReadClientTests {

  private static let secret = "placeholder-read-token"
  private static let range = UmamiReadRange(
    startAt: Date(timeIntervalSince1970: 1_000), endAt: Date(timeIntervalSince1970: 2_000))

  private static func makeConfig(
    endpoint: String = "https://umami.example", token: String = secret
  ) throws -> UmamiReadConfig {
    try UmamiReadConfig(endpoint: URL(string: endpoint)!, websiteId: "site-1", token: token)
  }

  private static func query(_ request: URLRequest) -> [String: String] {
    let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
    return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
  }

  // MARK: - Config

  @Test("config rejects http unless opted in, an empty token and an empty website")
  func configValidation() throws {
    #expect(throws: UmamiReadConfigError.insecureHTTPNotAllowed) {
      _ = try Self.makeConfig(endpoint: "http://umami.example")
    }
    #expect(throws: UmamiReadConfigError.emptyToken) { _ = try Self.makeConfig(token: "") }
    #expect(throws: UmamiReadConfigError.emptyWebsiteId) {
      _ = try UmamiReadConfig(
        endpoint: URL(string: "https://umami.example")!, websiteId: "", token: "t")
    }
    #expect(throws: UmamiReadConfigError.unsupportedScheme("ftp")) {
      _ = try Self.makeConfig(endpoint: "ftp://umami.example")
    }
    let local = try UmamiReadConfig(
      endpoint: URL(string: "http://localhost:3000")!, websiteId: "s", token: "t",
      allowInsecureHTTP: true)
    #expect(local.port == 3000)
  }

  @Test("the token is never part of description, debugDescription, dump or interpolation")
  func tokenIsRedacted() throws {
    let config = try Self.makeConfig()
    var dumped = ""
    dump(config, to: &dumped)
    let rendered = [
      config.description, config.debugDescription, "\(config)", String(reflecting: config), dumped,
    ]
    for text in rendered { #expect(!text.contains(Self.secret)) }
    #expect(config.description.contains("<redacted>"))
  }

  // MARK: - Endpoints

  @Test("stats hits /api/websites/:id/stats with a millisecond window and the bearer")
  func statsRequest() async throws {
    let mock = MockNetworkService()
    mock.resultData = Data(#"{"pageviews":{"value":5,"prev":2},"visitors":3}"#.utf8)
    let stats = try await UmamiReadClient(networkService: mock, config: try Self.makeConfig())
      .stats(in: Self.range)

    let request = try #require(mock.capturedRequests.first)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.host == "umami.example")
    #expect(request.url?.path == "/api/websites/site-1/stats")
    #expect(Self.query(request)["startAt"] == "1000000")
    #expect(Self.query(request)["endAt"] == "2000000")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.secret)")
    #expect(request.httpBody == nil)
    #expect(stats.pageviews == UmamiStatValue(value: 5, prev: 2))
    #expect(stats.visitors == UmamiStatValue(value: 3))
    #expect(stats.bounces == nil)
  }

  @Test("metrics carries the type and optional limit")
  func metricsRequest() async throws {
    let mock = MockNetworkService()
    mock.resultData = Data(#"[{"x":"a","y":1}]"#.utf8)
    let client = UmamiReadClient(networkService: mock, config: try Self.makeConfig())
    let rows = try await client.metrics(.event, in: Self.range, limit: 50)

    let request = try #require(mock.capturedRequests.first)
    #expect(request.url?.path == "/api/websites/site-1/metrics")
    #expect(Self.query(request)["type"] == "event")
    #expect(Self.query(request)["limit"] == "50")
    #expect(rows == [UmamiMetricRow(x: "a", y: 1)])
  }

  @Test("events pages and only sends search when set")
  func eventsRequest() async throws {
    let mock = MockNetworkService()
    mock.resultData = Data(
      #"{"data":[{"eventName":"shikki.verb.exit","urlPath":"/cli"}],"count":1,"page":2,"pageSize":10}"#
        .utf8)
    let client = UmamiReadClient(networkService: mock, config: try Self.makeConfig())
    let page = try await client.events(in: Self.range, search: "shikki", page: 2, pageSize: 10)
    _ = try await client.events(in: Self.range)

    #expect(Self.query(mock.capturedRequests[0])["search"] == "shikki")
    #expect(Self.query(mock.capturedRequests[0])["page"] == "2")
    #expect(Self.query(mock.capturedRequests[0])["pageSize"] == "10")
    #expect(Self.query(mock.capturedRequests[1])["search"] == nil)
    #expect(page.data.first?.eventName == "shikki.verb.exit")
    #expect(page.count == 1)
  }

  @Test("pageViews, eventSeries and active use their own paths")
  func otherPaths() async throws {
    let mock = MockNetworkService()
    let client = UmamiReadClient(networkService: mock, config: try Self.makeConfig())

    mock.resultData = Data(#"{"pageviews":[{"x":"d","y":1}],"sessions":[]}"#.utf8)
    _ = try await client.pageViews(in: Self.range, unit: .hour, timezone: "Europe/Paris")
    mock.resultData = Data(#"[{"x":"d","y":2}]"#.utf8)
    _ = try await client.eventSeries(in: Self.range)
    mock.resultData = Data(#"{"visitors":4}"#.utf8)
    let active = try await client.active()

    #expect(mock.capturedRequests.map { $0.url?.path } == [
      "/api/websites/site-1/pageviews", "/api/websites/site-1/events/series",
      "/api/websites/site-1/active",
    ])
    #expect(Self.query(mock.capturedRequests[0])["unit"] == "hour")
    #expect(Self.query(mock.capturedRequests[0])["timezone"] == "Europe/Paris")
    #expect(Self.query(mock.capturedRequests[2]).isEmpty)
    #expect(active.visitors == 4)
  }

  // MARK: - eventCount: the question that motivated the extraction

  @Test("eventCount returns the count of the named event and 0 when umami has no such row")
  func eventCount() async throws {
    let mock = MockNetworkService()
    mock.resultData = Data(#"[{"x":"shikki.verb.exit","y":7},{"x":"other","y":1}]"#.utf8)
    let client = UmamiReadClient(networkService: mock, config: try Self.makeConfig())

    #expect(try await client.eventCount(named: "shikki.verb.exit", in: Self.range) == 7)
    #expect(try await client.eventCount(named: "shikki.verb.absent", in: Self.range) == 0)
    #expect(Self.query(mock.capturedRequests[0])["type"] == "event")
  }

  @Test("a transport error propagates unchanged")
  func errorPropagates() async throws {
    let mock = MockNetworkService()
    mock.resultError = .unexpectedStatusCode(401)
    let client = UmamiReadClient(networkService: mock, config: try Self.makeConfig())
    await #expect(throws: NetworkError.self) { _ = try await client.stats(in: Self.range) }
  }

  // MARK: - The send path never carries a read token

  @Test("the send path stays unauthenticated and never uses a read endpoint")
  func sendPathNeverCarriesAToken() throws {
    let send = try UmamiConfig(
      endpoint: URL(string: "https://umami.example")!, websiteId: "site-1", hostname: "com.example.app")
    let track = UmamiEndPoint.track(config: send, url: "/cli", title: "t")
    #expect(track.header?["Authorization"] == nil)
    #expect(track.path == "/send")

    let read = try Self.makeConfig()
    let endpoints: [UmamiReadEndPoint] = [
      .stats(config: read, range: Self.range),
      .metrics(config: read, range: Self.range, type: .event, limit: nil),
      .events(config: read, range: Self.range, search: nil, page: 1, pageSize: 20),
      .active(config: read),
    ]
    for endpoint in endpoints {
      #expect(endpoint.method == .GET)
      #expect(!endpoint.path.hasSuffix("/send"))
      #expect(endpoint.body == nil)
    }
  }
}

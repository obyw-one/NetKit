//
//  UmamiEndPointTests.swift
//  NetKitTests
//
//  W1 T-01–T-04, T-06 — the umami wire contract.
//

import Foundation
import Testing

@testable import NetKit

@Suite("UmamiEndPoint")
struct UmamiEndPointTests {

  // MARK: - Fixtures

  private static let endpoint = URL(string: "https://umami.example")!

  private static func makeConfig(
    endpoint: URL = UmamiEndPointTests.endpoint,
    websiteId: String = "site-1",
    hostname: String = "com.example.app",
    appName: String = "MyApp",
    displayName: String = "My App: The Reckoning",
    language: String = "en-US",
    screen: String = "1920x1080",
    os: String = "iOS 17.0",
    userAgent: String = "MyApp/1.0 (iPhone; iOS 17.0)",
    device: String = "iPhone15,3",
    id: String? = nil,
    userId: String? = nil,
    authorization: String? = nil,
    allowInsecureHTTP: Bool = false
  ) throws -> UmamiConfig {
    try UmamiConfig(
      endpoint: endpoint,
      websiteId: websiteId,
      hostname: hostname,
      appName: appName,
      displayName: displayName,
      language: language,
      screen: screen,
      os: os,
      userAgent: userAgent,
      device: device,
      id: id,
      userId: userId,
      authorization: authorization,
      allowInsecureHTTP: allowInsecureHTTP
    )
  }

  // MARK: - T-01

  @Test("T-01 track builds POST https://<host>/api/send with headers, no Authorization by default")
  func t01_requestShape() throws {
    let config = try Self.makeConfig()
    let endPoint = UmamiEndPoint.track(config: config, url: "/cli", title: "shikki.verb.exit")
    let service = NetworkService()

    let request = service.createRequest(endPoint: endPoint)

    #expect(request.httpMethod == "POST")
    #expect(request.url?.scheme == "https")
    #expect(request.url?.host == "umami.example")
    let requestPath = request.url?.path ?? ""
    #expect(requestPath == "/api/send")
    // Foundation normalises header casing on URLRequest; use
    // `value(forHTTPHeaderField:)`, which is case-insensitive.
    #expect(request.value(forHTTPHeaderField: "accept") == "application/json")
    #expect(request.value(forHTTPHeaderField: "User-Agent") == config.userAgent)
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
  }

  @Test("T-01 Authorization is attached when config.authorization is set")
  func t01_authorizationAttachedWhenConfigured() throws {
    let config = try Self.makeConfig(authorization: "Bearer secret-token")
    let endPoint = UmamiEndPoint.track(config: config, url: "/cli", title: "shikki.verb.exit")
    let service = NetworkService()

    let request = service.createRequest(endPoint: endPoint)

    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token")
  }

  // MARK: - T-02

  @Test(
    "T-02 body shape — payload fields present, os/browser absent at top level, data merges params")
  func t02_bodyShape() throws {
    let config = try Self.makeConfig()
    let endPoint = UmamiEndPoint.track(
      config: config,
      url: "/cli",
      title: "shikki.verb.exit",
      params: ["shi_version": "0.9.1", "posture": "healthy"]
    )

    let body = try #require(endPoint.body)
    #expect(body["type"] as? String == "event")

    let payload = try #require(body["payload"] as? [String: Any])

    #expect(payload["website"] as? String == "site-1")
    #expect(payload["hostname"] as? String == "com.example.app")
    #expect(payload["host"] as? String == "com.example.app")
    #expect(payload["language"] as? String == "en-US")
    #expect(payload["screen"] as? String == "1920x1080")
    #expect(payload["title"] as? String == "shikki.verb.exit")
    #expect(payload["url"] as? String == "/cli")
    #expect(payload["User-Agent"] as? String == config.userAgent)

    // os/browser MUST stay OUT of the top level — umami returns HTTP 500 otherwise.
    #expect(payload["os"] == nil)
    #expect(payload["browser"] == nil)

    let data = try #require(payload["data"] as? [String: String])
    #expect(data["hostname"] == "com.example.app")
    #expect(data["appname"] == "MyApp")
    #expect(data["displayname"] == "My App: The Reckoning")
    #expect(data["device"] == "iPhone15,3")
    #expect(data["os"] == "iOS 17.0")
    #expect(data["User-Agent"] == config.userAgent)
    // Caller-supplied params merged over defaults.
    #expect(data["shi_version"] == "0.9.1")
    #expect(data["posture"] == "healthy")
  }

  @Test("T-02 caller-supplied params override default data keys")
  func t02_paramsOverrideDefaults() throws {
    let config = try Self.makeConfig()
    let endPoint = UmamiEndPoint.track(
      config: config,
      url: "/cli",
      title: "t",
      params: ["appname": "override", "hostname": "override.host"]
    )

    let body = try #require(endPoint.body)
    let payload = try #require(body["payload"] as? [String: Any])
    let data = try #require(payload["data"] as? [String: String])

    #expect(data["appname"] == "override")
    #expect(data["hostname"] == "override.host")
    // Top-level hostname is NOT overridden by data merge — it comes from config.
    #expect(payload["hostname"] as? String == "com.example.app")
  }

  // MARK: - T-03

  @Test("T-03 id/userId/referrer/tag only appear when non-nil")
  func t03_optionalFieldsGatedByPresence() throws {
    let bare = try Self.makeConfig()
    let bareEndPoint = UmamiEndPoint.track(config: bare, url: "/cli", title: "t")
    let barePayload = try #require((bareEndPoint.body?["payload"]) as? [String: Any])
    #expect(barePayload["id"] == nil)
    #expect(barePayload["userId"] == nil)
    #expect(barePayload["referrer"] == nil)
    #expect(barePayload["tag"] == nil)

    let filled = try Self.makeConfig(id: "sess-42", userId: "user-7")
    let filledEndPoint = UmamiEndPoint.track(
      config: filled,
      url: "/cli",
      title: "t",
      referrer: "/prev",
      tag: "cta-primary"
    )
    let filledPayload = try #require((filledEndPoint.body?["payload"]) as? [String: Any])
    #expect(filledPayload["id"] as? String == "sess-42")
    #expect(filledPayload["userId"] as? String == "user-7")
    #expect(filledPayload["referrer"] as? String == "/prev")
    #expect(filledPayload["tag"] as? String == "cta-primary")
  }

  // MARK: - T-04

  @Test("T-04 https endpoint is accepted")
  func t04_acceptsHTTPS() throws {
    _ = try Self.makeConfig(endpoint: URL(string: "https://umami.example")!)
  }

  @Test("T-04 http is refused unless allowInsecureHTTP is true")
  func t04_rejectsHTTPByDefault() {
    #expect(throws: UmamiConfigError.insecureHTTPNotAllowed) {
      _ = try Self.makeConfig(endpoint: URL(string: "http://umami.local")!)
    }
  }

  @Test("T-04 http is accepted when allowInsecureHTTP is true")
  func t04_acceptsHTTPWhenOptedIn() throws {
    let config = try Self.makeConfig(
      endpoint: URL(string: "http://umami.local")!,
      allowInsecureHTTP: true
    )
    #expect(config.scheme == "http")
    #expect(config.host == "umami.local")
  }

  @Test("T-04 file:// scheme is refused")
  func t04_rejectsFileScheme() {
    #expect(throws: UmamiConfigError.self) {
      _ = try Self.makeConfig(endpoint: URL(string: "file:///tmp/x")!)
    }
  }

  @Test("T-04 data: scheme is refused")
  func t04_rejectsDataScheme() {
    #expect(throws: UmamiConfigError.self) {
      _ = try Self.makeConfig(endpoint: URL(string: "data:text/plain,hello")!)
    }
  }

  @Test("T-04 empty host is refused even when scheme is https")
  func t04_rejectsEmptyHost() {
    // "https:///path" parses as https with a nil/empty host.
    let url = URL(string: "https:///path")!
    #expect(throws: UmamiConfigError.self) {
      _ = try UmamiConfig(endpoint: url, websiteId: "w", hostname: "h")
    }
  }

  // MARK: - T-06 — wire fidelity with the WabiSabi consumer

  @Test("T-06 serialised body matches WabiSabi's `UmamiEndPoint.body` shape byte-for-byte")
  func t06_matchesWabiSabiPayload() throws {
    // Fixture inputs taken from the WabiSabi flow at e026cd6:
    //   - config.websiteId  = "wsb-1"
    //   - config.hostname   = "com.example.wabisabi"
    //   - config.appName    = "WabiSabi"
    //   - config.displayName= "WabiSabi: Habits"
    //   - config.language   = "fr-FR"
    //   - config.screen     = "1179x2556"
    //   - DeviceInfo.osVersion = "iOS 17.4"
    //   - DeviceInfo.userAgent = "WabiSabi/1.0 (iPhone; iOS 17.4)"
    //   - config.device     = "iPhone15,3"
    //   - track(url: "/home", title: "Home", params: ["view": "list"])
    let config = try UmamiConfig(
      endpoint: URL(string: "https://umami.wabisabi.app")!,
      websiteId: "wsb-1",
      hostname: "com.example.wabisabi",
      appName: "WabiSabi",
      displayName: "WabiSabi: Habits",
      language: "fr-FR",
      screen: "1179x2556",
      os: "iOS 17.4",
      userAgent: "WabiSabi/1.0 (iPhone; iOS 17.4)",
      device: "iPhone15,3"
    )
    let endPoint = UmamiEndPoint.track(
      config: config,
      url: "/home",
      title: "Home",
      params: ["view": "list"]
    )

    // Serialise → parse: this is what the wire would carry, order-agnostic.
    let body = try #require(endPoint.body)
    let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    let parsed = try #require(
      try JSONSerialization.jsonObject(with: data) as? [String: Any]
    )

    // Fixture produced by hand-running the WabiSabi body for the same inputs
    // at commit e026cd6. If umami's wire contract drifts, this test breaks.
    let expected: [String: Any] = [
      "type": "event",
      "payload": [
        "website": "wsb-1",
        "hostname": "com.example.wabisabi",
        "host": "com.example.wabisabi",
        "language": "fr-FR",
        "screen": "1179x2556",
        "title": "Home",
        "url": "/home",
        "User-Agent": "WabiSabi/1.0 (iPhone; iOS 17.4)",
        "data": [
          "hostname": "com.example.wabisabi",
          "appname": "WabiSabi",
          "displayname": "WabiSabi: Habits",
          "device": "iPhone15,3",
          "os": "iOS 17.4",
          "User-Agent": "WabiSabi/1.0 (iPhone; iOS 17.4)",
          "view": "list",
        ] as [String: String],
      ] as [String: Any],
    ]
    let expectedData = try JSONSerialization.data(withJSONObject: expected, options: [.sortedKeys])
    let expectedParsed = try #require(
      try JSONSerialization.jsonObject(with: expectedData) as? [String: Any]
    )

    // Compare via NSDictionary equality: it walks nested dicts and treats
    // NSNumber/NSString / [String: Any] uniformly. Field-by-field NSDictionary
    // equality is the accepted way to compare JSON-serialised `[String: Any]`.
    #expect(NSDictionary(dictionary: parsed) == NSDictionary(dictionary: expectedParsed))
  }
}

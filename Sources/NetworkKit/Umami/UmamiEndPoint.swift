//
//  UmamiEndPoint.swift
//  NetworkKit
//
//  Upstreamed from WabiSabi (Core/Abstracts/Data Layer/Repositories) — 2026-09-09.
//  The umami wire contract for `POST /api/send`. The associated `UmamiConfig`
//  travels with the case so the endpoint has no global state (BR-UMA-01/02).
//

import Foundation

public enum UmamiEndPoint: EndPoint, @unchecked Sendable {

  /// Track a single umami event.
  ///
  /// - Parameters:
  ///   - config:   Validated ``UmamiConfig`` — provides host, scheme, user-agent
  ///               and optional `Authorization`.
  ///   - url:      Virtual page path recorded by umami (e.g. `/cli`).
  ///   - title:    Event title (umami stores it in the events table).
  ///   - referrer: Optional `document.referrer` analogue. Only emitted when set.
  ///   - tag:      Optional umami tag. Only emitted when set.
  ///   - params:   Caller-supplied event data. Merged over the config-derived
  ///               defaults inside the `data` object — later keys win.
  case track(
    config: UmamiConfig,
    url: String,
    title: String,
    referrer: String? = nil,
    tag: String? = nil,
    params: [String: String] = [:]
  )

  // MARK: - EndPoint

  public var scheme: String {
    switch self {
    case .track(let config, _, _, _, _, _): return config.scheme
    }
  }

  public var host: String {
    switch self {
    case .track(let config, _, _, _, _, _): return config.host
    }
  }

  public var port: Int? { nil }

  public var apiPath: String { "/api" }

  public var apiFilePath: String { "" }

  public var path: String {
    switch self {
    case .track: return "/send"
    }
  }

  public var method: RequestMethod { .POST }

  public var header: [String: String]? {
    switch self {
    case .track(let config, _, _, _, _, _):
      var header: [String: String] = [
        "accept": "application/json",
        "User-Agent": config.userAgent,
      ]
      if let authorization = config.authorization {
        header["Authorization"] = authorization
      }
      return header
    }
  }

  public var body: [String: Any]? {
    switch self {
    case .track(let config, let url, let title, let referrer, let tag, let params):
      var payload: [String: Any] = [
        "website": config.websiteId,
        "hostname": config.hostname,
        "host": config.hostname,
        // "os":      config.os,        // top-level → HTTP 500 (kept as a test)
        // "browser": config.userAgent, // top-level → HTTP 500 (kept as a test)
        "language": config.language,
        "screen": config.screen,
      ]

      if let id = config.id { payload["id"] = id }
      if let userId = config.userId { payload["userId"] = userId }

      payload["title"] = title
      payload["url"] = url
      payload["User-Agent"] = config.userAgent
      if let referrer = referrer { payload["referrer"] = referrer }
      if let tag = tag { payload["tag"] = tag }

      let defaultData: [String: String] = [
        "hostname": config.hostname,
        "appname": config.appName,
        "displayname": config.displayName,
        "device": config.device,
        "os": config.os,
        "User-Agent": config.userAgent,
      ]
      payload["data"] = defaultData.merging(params) { _, new in new }

      return ["type": "event", "payload": payload]
    }
  }

  public var queryParams: [String: Any]? { nil }
}

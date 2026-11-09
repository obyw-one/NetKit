//
//  UmamiReadEndPoint.swift
//  NetworkKit
//
//  The umami QUERY endpoints (GET, authenticated). Named ``UmamiReadEndPoint``
//  so it does not collide with the write-side ``UmamiEndPoint``. Every case
//  carries its ``UmamiReadConfig``, so there is no global state and no
//  hardcoded URL.
//

import Foundation

/// A closed time window, sent to umami as epoch milliseconds.
public struct UmamiReadRange: Equatable, Sendable {
  public let startAt: Date
  public let endAt: Date

  public init(startAt: Date, endAt: Date) {
    self.startAt = startAt
    self.endAt = endAt
  }

  /// The window ending at `now` and reaching back `seconds`.
  public static func last(seconds: TimeInterval, now: Date = Date()) -> UmamiReadRange {
    UmamiReadRange(startAt: now.addingTimeInterval(-seconds), endAt: now)
  }

  var startMilliseconds: String { String(Int64(startAt.timeIntervalSince1970 * 1000)) }
  var endMilliseconds: String { String(Int64(endAt.timeIntervalSince1970 * 1000)) }
}

/// What `GET /websites/:id/metrics` groups by.
public enum UmamiMetricType: String, Sendable, CaseIterable {
  case url, referrer, browser, os, device, country, region, city, language, screen, event, title,
    host, tag, path
}

/// The time bucket for series endpoints.
public enum UmamiReadUnit: String, Sendable {
  case minute, hour, day, month, year
}

public enum UmamiReadEndPoint: EndPoint, @unchecked Sendable {

  /// `GET /api/websites/:id/stats`
  case stats(config: UmamiReadConfig, range: UmamiReadRange)
  /// `GET /api/websites/:id/pageviews`
  case pageViews(config: UmamiReadConfig, range: UmamiReadRange, unit: UmamiReadUnit, timezone: String)
  /// `GET /api/websites/:id/metrics?type=…` — with `.event` this is the per-name event count.
  case metrics(config: UmamiReadConfig, range: UmamiReadRange, type: UmamiMetricType, limit: Int?)
  /// `GET /api/websites/:id/events` — the raw event rows, paged.
  case events(
    config: UmamiReadConfig, range: UmamiReadRange, search: String?, page: Int, pageSize: Int)
  /// `GET /api/websites/:id/events/series`
  case eventSeries(
    config: UmamiReadConfig, range: UmamiReadRange, unit: UmamiReadUnit, timezone: String)
  /// `GET /api/websites/:id/active` — visitors in the last five minutes.
  case active(config: UmamiReadConfig)

  private var config: UmamiReadConfig {
    switch self {
    case .stats(let c, _), .pageViews(let c, _, _, _), .metrics(let c, _, _, _),
      .events(let c, _, _, _, _), .eventSeries(let c, _, _, _), .active(let c):
      return c
    }
  }

  // MARK: - EndPoint

  public var scheme: String { config.scheme }
  public var host: String { config.host }
  public var port: Int? { config.port }
  public var apiPath: String { "/api" }
  public var apiFilePath: String { "" }

  public var path: String {
    let base = "/websites/\(config.websiteId)"
    switch self {
    case .stats: return base + "/stats"
    case .pageViews: return base + "/pageviews"
    case .metrics: return base + "/metrics"
    case .events: return base + "/events"
    case .eventSeries: return base + "/events/series"
    case .active: return base + "/active"
    }
  }

  public var method: RequestMethod { .GET }

  public var header: [String: String]? {
    [
      "accept": "application/json",
      "Authorization": config.authorizationHeader,
    ]
  }

  public var body: [String: Any]? { nil }

  public var queryParams: [String: Any]? {
    // Values stay Strings: `[URLQueryItem](from:)` turns any other type into "-".
    switch self {
    case .stats(_, let range):
      return window(range)
    case .pageViews(_, let range, let unit, let timezone),
      .eventSeries(_, let range, let unit, let timezone):
      return window(range).merging(["unit": unit.rawValue, "timezone": timezone]) { _, new in new }
    case .metrics(_, let range, let type, let limit):
      var query = window(range).merging(["type": type.rawValue]) { _, new in new }
      if let limit { query["limit"] = String(limit) }
      return query
    case .events(_, let range, let search, let page, let pageSize):
      var query = window(range).merging(["page": String(page), "pageSize": String(pageSize)]) {
        _, new in new
      }
      if let search, !search.isEmpty { query["search"] = search }
      return query
    case .active:
      return nil
    }
  }

  private func window(_ range: UmamiReadRange) -> [String: String] {
    ["startAt": range.startMilliseconds, "endAt": range.endMilliseconds]
  }
}

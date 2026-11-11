//
//  UmamiReadModels.swift
//  NetworkKit
//
//  Decodable shapes for the umami query endpoints. Like ``UmamiAnswer``, every
//  field that umami may omit is optional: the wire is the contract, not the
//  richest answer.
//

import Foundation

/// One bucket of `/metrics`: `x` is the dimension value (for `type=event`, the
/// event name) and `y` its count.
public struct UmamiMetricRow: Codable, Equatable, Sendable {
  public let x: String
  public let y: Int
  public init(x: String, y: Int) {
    self.x = x
    self.y = y
  }
}

/// A `{ value, prev }` pair as umami reports each `/stats` figure.
public struct UmamiStatValue: Codable, Equatable, Sendable {
  public let value: Double?
  public let prev: Double?
  public init(value: Double? = nil, prev: Double? = nil) {
    self.value = value
    self.prev = prev
  }
}

/// `/stats`. Older umami returns bare numbers, newer returns ``UmamiStatValue``;
/// both decode into ``UmamiStatValue``.
public struct UmamiReadStats: Codable, Equatable, Sendable {
  public let pageviews: UmamiStatValue?
  public let visitors: UmamiStatValue?
  public let visits: UmamiStatValue?
  public let bounces: UmamiStatValue?
  public let totaltime: UmamiStatValue?

  private enum CodingKeys: String, CodingKey {
    case pageviews, visitors, visits, bounces, totaltime
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    func stat(_ key: CodingKeys) -> UmamiStatValue? {
      if let v = try? c.decode(UmamiStatValue.self, forKey: key) { return v }
      if let n = try? c.decode(Double.self, forKey: key) { return UmamiStatValue(value: n) }
      return nil
    }
    pageviews = stat(.pageviews)
    visitors = stat(.visitors)
    visits = stat(.visits)
    bounces = stat(.bounces)
    totaltime = stat(.totaltime)
  }
}

/// A point of a time series (`/pageviews`, `/events/series`).
public struct UmamiSeriesPoint: Codable, Equatable, Sendable {
  public let x: String
  public let y: Int
  public init(x: String, y: Int) {
    self.x = x
    self.y = y
  }
}

/// `/pageviews`: two parallel series.
public struct UmamiPageViewSeries: Codable, Equatable, Sendable {
  public let pageviews: [UmamiSeriesPoint]?
  public let sessions: [UmamiSeriesPoint]?
  public init(pageviews: [UmamiSeriesPoint]? = nil, sessions: [UmamiSeriesPoint]? = nil) {
    self.pageviews = pageviews
    self.sessions = sessions
  }
}

/// One raw event row from `/events`.
public struct UmamiEventRow: Codable, Equatable, Sendable {
  public let id: String?
  public let eventName: String?
  public let urlPath: String?
  public let createdAt: String?
  public let sessionId: String?
  public init(
    id: String? = nil, eventName: String? = nil, urlPath: String? = nil,
    createdAt: String? = nil, sessionId: String? = nil
  ) {
    self.id = id
    self.eventName = eventName
    self.urlPath = urlPath
    self.createdAt = createdAt
    self.sessionId = sessionId
  }
}

/// `/events`: a page of rows plus the total count.
public struct UmamiEventPage: Codable, Equatable, Sendable {
  public let data: [UmamiEventRow]
  public let count: Int?
  public let page: Int?
  public let pageSize: Int?
  public init(data: [UmamiEventRow], count: Int? = nil, page: Int? = nil, pageSize: Int? = nil) {
    self.data = data
    self.count = count
    self.page = page
    self.pageSize = pageSize
  }
}

/// `/active`.
public struct UmamiActiveVisitors: Codable, Equatable, Sendable {
  public let visitors: Int?
  public init(visitors: Int? = nil) { self.visitors = visitors }
}

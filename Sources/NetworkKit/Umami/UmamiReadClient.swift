//
//  UmamiReadClient.swift
//  NetworkKit
//
//  Reads data back from umami through the injected ``NetworkProtocol``. This is
//  what turns "did the event land?" from a dashboard visit into a call a test
//  can make: spec 9e1c4a77's acceptance criterion is a `shikki.verb.*` row
//  visible in the Events view, and ``eventCount(named:in:)`` reads exactly that.
//

import Foundation

public struct UmamiReadClient: Sendable {

  private let networkService: NetworkProtocol
  private let config: UmamiReadConfig

  public init(networkService: NetworkProtocol, config: UmamiReadConfig) {
    self.networkService = networkService
    self.config = config
  }

  public func stats(in range: UmamiReadRange) async throws -> UmamiReadStats {
    try await networkService.sendRequest(endpoint: UmamiReadEndPoint.stats(config: config, range: range))
  }

  public func pageViews(
    in range: UmamiReadRange, unit: UmamiReadUnit = .day, timezone: String = "UTC"
  ) async throws -> UmamiPageViewSeries {
    try await networkService.sendRequest(
      endpoint: UmamiReadEndPoint.pageViews(
        config: config, range: range, unit: unit, timezone: timezone))
  }

  public func metrics(
    _ type: UmamiMetricType, in range: UmamiReadRange, limit: Int? = nil
  ) async throws -> [UmamiMetricRow] {
    try await networkService.sendRequest(
      endpoint: UmamiReadEndPoint.metrics(config: config, range: range, type: type, limit: limit))
  }

  public func events(
    in range: UmamiReadRange, search: String? = nil, page: Int = 1, pageSize: Int = 20
  ) async throws -> UmamiEventPage {
    try await networkService.sendRequest(
      endpoint: UmamiReadEndPoint.events(
        config: config, range: range, search: search, page: page, pageSize: pageSize))
  }

  public func eventSeries(
    in range: UmamiReadRange, unit: UmamiReadUnit = .hour, timezone: String = "UTC"
  ) async throws -> [UmamiSeriesPoint] {
    try await networkService.sendRequest(
      endpoint: UmamiReadEndPoint.eventSeries(
        config: config, range: range, unit: unit, timezone: timezone))
  }

  public func active() async throws -> UmamiActiveVisitors {
    try await networkService.sendRequest(endpoint: UmamiReadEndPoint.active(config: config))
  }

  /// How many times the named custom event was recorded in `range`. Zero when
  /// umami has no row for that name — which is the answer a bot-rejected `200`
  /// produces, and the reason a send's HTTP status alone proves nothing.
  public func eventCount(named name: String, in range: UmamiReadRange) async throws -> Int {
    let rows = try await metrics(.event, in: range)
    return rows.first(where: { $0.x == name })?.y ?? 0
  }
}

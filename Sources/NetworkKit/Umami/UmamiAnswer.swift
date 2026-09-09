//
//  UmamiAnswer.swift
//  NetworkKit
//
//  Upstreamed from WabiSabi (Core/Abstracts/Data Layer/Models) — 2026-09-09.
//

import Foundation

public struct UmamiAnswer: Codable, Equatable, Sendable {
  public let cache: String
  public let sessionId: String
  public let visitId: String

  public init(cache: String, sessionId: String, visitId: String) {
    self.cache = cache
    self.sessionId = sessionId
    self.visitId = visitId
  }

  enum CodingKeys: String, CodingKey {
    case cache, sessionId, visitId
  }
}

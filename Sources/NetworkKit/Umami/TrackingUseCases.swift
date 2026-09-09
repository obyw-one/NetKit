//
//  TrackingUseCases.swift
//  NetworkKit
//
//  Upstreamed from WabiSabi (Core/Abstracts/Domain/UseCases) — 2026-09-09.
//

import Foundation

public enum TrackUseCaseError: Error, CustomStringConvertible, Sendable {
  case networkError

  public var description: String {
    switch self {
    case .networkError: return "Network error"
    }
  }
}

public protocol TrackUseCaseProtocol: Sendable {
  associatedtype ResponseModel: Codable & Sendable

  @discardableResult
  func execute(_ params: TrackInfoProtocol) async throws(TrackUseCaseError) -> ResponseModel
}

public protocol TrackInfoProtocol: Sendable {
  var url: String { get }
  var title: String { get }
  var referrer: String? { get }
  var tag: String? { get }
  var extra: [String: String] { get }
}

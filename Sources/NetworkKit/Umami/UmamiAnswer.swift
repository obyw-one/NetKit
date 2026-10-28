//
//  UmamiAnswer.swift
//  NetworkKit
//
//  Upstreamed from WabiSabi (Core/Abstracts/Data Layer/Models) — 2026-09-09.
//

import Foundation

/// A umami `/api/send` acknowledgement.
///
/// **Every field is optional, and that is the contract — not a convenience.**
///
/// The first version of this type declared `cache`, `sessionId` and `visitId`
/// as non-optional `String`. That modelled umami's RICHEST answer and not its
/// contract: `/api/send` is free to answer with the full object, with a bare
/// token, with `{}`, or with an empty body, and every one of those means the
/// event was ACCEPTED.
///
/// The cost of the stricter shape was measured, not theorised. In shikki,
/// `NetworkProtocol.sendRequest` guards `200..<400` and throws
/// `unexpectedStatusCode` BEFORE decoding, then maps `DecodingError` to
/// `NetworkError.jsonParsingFailed`. So a thin answer to a SUCCESSFUL POST
/// surfaced as a decode failure, the caller recorded the event as undelivered,
/// and its replay journal retried it forever — 12 telemetry payloads were stuck
/// from 2026-10-23 to 2026-10-28, re-failing on every CLI invocation.
///
/// Optionality here is therefore the honest shape of the wire. A consumer that
/// genuinely needs `sessionId` should `guard` on it and say why, rather than
/// have the decoder reject a delivery on its behalf.
///
/// What this type deliberately does NOT decide is whether an undecodable body
/// still counts as delivered. That is the consumer's policy — a telemetry
/// journal may ack it, while a session-establishing call may not — so it stays
/// out of NetworkKit.
public struct UmamiAnswer: Codable, Equatable, Sendable {

  /// umami's cache token, when the deployment returns one.
  public let cache: String?

  /// The session umami attributed the event to, when it reports one.
  public let sessionId: String?

  /// The visit umami attributed the event to, when it reports one.
  public let visitId: String?

  public init(cache: String? = nil, sessionId: String? = nil, visitId: String? = nil) {
    self.cache = cache
    self.sessionId = sessionId
    self.visitId = visitId
  }

  enum CodingKeys: String, CodingKey {
    case cache, sessionId, visitId
  }

  /// Decodes leniently: a missing key yields `nil` rather than failing the
  /// whole answer, so `{}` and a partial object both decode.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    cache = try container.decodeIfPresent(String.self, forKey: .cache)
    sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
    visitId = try container.decodeIfPresent(String.self, forKey: .visitId)
  }
}

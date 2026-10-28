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
/// token, with `{}`, or with an empty body.
///
/// **CORRECTION (2.4.0).** The v2.2.1 header said every one of those "means
/// the event was ACCEPTED". That is false, and it was the most expensive
/// sentence in this file: umami answers HTTP **200** with `{"beep":"boop"}`
/// when its bot filter DISCARDS an event. A consumer following this type's own
/// documentation would ack a rejection and delete the payload — which is
/// exactly what shikki did, losing a telemetry buffer on 2026-10-28.
///
/// `beep` and ``acceptance`` exist so that can no longer happen to anyone.
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

  /// Present (as `"boop"`) ONLY when umami's bot filter DISCARDED the event.
  ///
  /// umami answers that rejection with HTTP **200** and the body
  /// `{"beep":"boop"}`, so without this key an acceptance and a discard decode
  /// to the same all-nil value and no consumer can tell them apart. Measured
  /// 2026-10-28 against a live deployment — six User-Agent variants, and every
  /// one lacking an OS token came back `{"beep":"boop"}`.
  public let beep: String?

  public init(
    cache: String? = nil,
    sessionId: String? = nil,
    visitId: String? = nil,
    beep: String? = nil
  ) {
    self.cache = cache
    self.sessionId = sessionId
    self.visitId = visitId
    self.beep = beep
  }

  enum CodingKeys: String, CodingKey {
    case cache, sessionId, visitId, beep
  }

  /// Decodes leniently: a missing key yields `nil` rather than failing the
  /// whole answer, so `{}` and a partial object both decode.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    cache = try container.decodeIfPresent(String.self, forKey: .cache)
    sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
    visitId = try container.decodeIfPresent(String.self, forKey: .visitId)
    beep = try container.decodeIfPresent(String.self, forKey: .beep)
  }

  // MARK: - Acceptance

  /// What the answer says about the EVENT, as opposed to the request.
  ///
  /// A 2xx means the request arrived. It does not mean the event was
  /// recorded — umami answers 200 to a bot-rejection too. These are the three
  /// distinguishable outcomes, and only ``accepted`` may be treated as
  /// delivered.
  ///
  /// This lives in NetworkKit because it is the WIRE CONTRACT: what a given
  /// body means is the same for every consumer. What to DO about it — ack a
  /// replay journal, keep the payload, fail a screen — stays the consumer's
  /// policy, exactly as the type's header has always said.
  public enum Acceptance: Sendable, Equatable {
    /// umami attributed the event to a session, visit or cache — RECORDED.
    case accepted
    /// umami answered `{"beep":"boop"}`: its bot filter DISCARDED the event.
    case botRejected
    /// A 2xx carrying no acceptance evidence and no rejection marker.
    /// Delivery is UNKNOWN, not denied — `{}` and an empty body land here.
    case unrecognised
  }

  /// Classify this answer.
  ///
  /// Rejection is checked FIRST: a bot-rejection body carries no acceptance
  /// evidence, so the order only matters if umami ever sends both, and a
  /// rejection marker must win if it does.
  public var acceptance: Acceptance {
    if beep != nil { return .botRejected }
    if cache != nil || sessionId != nil || visitId != nil { return .accepted }
    return .unrecognised
  }
}

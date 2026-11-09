//
//  UmamiReadConfig.swift
//  NetworkKit
//
//  The READ side of umami. Deliberately a different type from ``UmamiConfig``:
//  `/api/send` takes no credential (BR-UMA-04 removed the bearer as a
//  disclosure vector), while every query endpoint requires one. Keeping the two
//  configs apart makes it impossible, by construction, to hand a read token to
//  ``UmamiEndPoint/track`` — the track endpoint only accepts a ``UmamiConfig``.
//

import Foundation

/// Errors thrown by ``UmamiReadConfig``. Validation happens once, at
/// construction, so a typo surfaces at boot rather than as an opaque 401.
public enum UmamiReadConfigError: Error, Equatable, Sendable, CustomStringConvertible {
  case emptyHost
  case emptyToken
  case emptyWebsiteId
  case unsupportedScheme(String?)
  case insecureHTTPNotAllowed

  public var description: String {
    switch self {
    case .emptyHost: return "Umami read endpoint host is empty."
    case .emptyToken: return "Umami read token is empty."
    case .emptyWebsiteId: return "Umami website id is empty."
    case .unsupportedScheme(let scheme):
      return
        "Umami read endpoint scheme \(scheme ?? "nil") is not supported (expected https, or http with allowInsecureHTTP: true)."
    case .insecureHTTPNotAllowed:
      return "Umami read endpoint scheme is http; pass allowInsecureHTTP: true to opt in."
    }
  }
}

/// Injected configuration for reading data back from umami.
///
/// Everything is supplied by the caller: no URL is baked in, no environment is
/// read. The token is carried as an opaque secret — it is never part of
/// `description`, `debugDescription` or the `Mirror` of this type, so a log line
/// that prints the config cannot leak it.
public struct UmamiReadConfig: Sendable, CustomStringConvertible, CustomDebugStringConvertible,
  CustomReflectable
{

  public let scheme: String
  public let host: String
  public let port: Int?
  public let websiteId: String
  private let token: String

  /// - Parameters:
  ///   - endpoint: Base URL of the umami server. Scheme, host and port are used.
  ///   - websiteId: The umami website (tenant) to read.
  ///   - token: A bearer token for the umami API, injected by the caller.
  ///   - allowInsecureHTTP: Accept an `http://` endpoint (a local umami).
  public init(
    endpoint: URL,
    websiteId: String,
    token: String,
    allowInsecureHTTP: Bool = false
  ) throws(UmamiReadConfigError) {
    switch endpoint.scheme?.lowercased() {
    case "https": self.scheme = "https"
    case "http":
      guard allowInsecureHTTP else { throw .insecureHTTPNotAllowed }
      self.scheme = "http"
    case let other: throw .unsupportedScheme(other)
    }
    guard let host = endpoint.host, !host.isEmpty else { throw .emptyHost }
    guard !token.isEmpty else { throw .emptyToken }
    guard !websiteId.isEmpty else { throw .emptyWebsiteId }
    self.host = host
    self.port = endpoint.port
    self.websiteId = websiteId
    self.token = token
  }

  /// The `Authorization` header value. Internal: only ``UmamiReadEndPoint``
  /// reads it, and nothing on the track path can.
  var authorizationHeader: String { "Bearer \(token)" }

  public var description: String {
    "UmamiReadConfig(\(scheme)://\(host), websiteId: \(websiteId), token: <redacted>)"
  }
  public var debugDescription: String { description }
  public var customMirror: Mirror {
    Mirror(
      self,
      children: ["scheme": scheme, "host": host, "websiteId": websiteId, "token": "<redacted>"],
      displayStyle: .struct)
  }
}

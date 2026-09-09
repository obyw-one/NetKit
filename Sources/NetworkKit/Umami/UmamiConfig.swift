//
//  UmamiConfig.swift
//  NetworkKit
//
//  Upstreamed from WabiSabi (Core/Abstracts/Data Layer/Repositories/UmamiEndPoint)
//  and de-app-ified: no Env, no DeviceInfo, no `.default`. Every value is injected
//  by the caller (BR-UMA-02). The endpoint URL is validated at construction time
//  so a config typo cannot silently kill telemetry at flush time (BR-UMA-03).
//

import Foundation

/// Errors thrown by ``UmamiConfig/init(endpoint:websiteId:hostname:appName:displayName:language:screen:os:userAgent:device:id:userId:authorization:allowInsecureHTTP:)``.
///
/// Validation is performed once, at construction, so misconfiguration surfaces
/// at boot rather than as an opaque HTTP failure on every flushed event.
public enum UmamiConfigError: Error, Equatable, Sendable, CustomStringConvertible {
  case emptyHost
  case unsupportedScheme(String?)
  case insecureHTTPNotAllowed

  public var description: String {
    switch self {
    case .emptyHost:
      return "Umami endpoint host is empty."
    case .unsupportedScheme(let scheme):
      return
        "Umami endpoint scheme \(scheme ?? "nil") is not supported (expected https, or http with allowInsecureHTTP: true)."
    case .insecureHTTPNotAllowed:
      return "Umami endpoint scheme is http; pass allowInsecureHTTP: true to opt in."
    }
  }
}

/// Injected configuration for an Umami tracker.
///
/// The umami server URL (scheme + host) travels with the config so the endpoint
/// enum has no global state. Everything else is a plain stored value supplied by
/// the caller — this type does not read process environment, bundle info or any
/// device APIs.
public struct UmamiConfig: Codable, Equatable, Sendable {

  // MARK: - Network

  /// URL scheme derived from the validated endpoint URL — always `https` or `http`.
  public let scheme: String
  /// Host derived from the validated endpoint URL — never empty.
  public let host: String
  /// Value sent verbatim as the `Authorization` header. When `nil`, no header
  /// is attached — umami's `/api/send` does not require authentication.
  public let authorization: String?

  // MARK: - Umami payload fields

  public let websiteId: String
  public let hostname: String
  public let appName: String
  public let displayName: String
  public let language: String
  public let screen: String
  public let os: String
  public let userAgent: String
  public let device: String
  public let id: String?
  public let userId: String?

  /// Build a validated Umami configuration.
  ///
  /// - Parameters:
  ///   - endpoint: Base URL of the umami server (e.g. `https://umami.example`).
  ///               Only scheme and host are consumed; path/query are ignored.
  ///   - websiteId: Umami "website id" — the tenant this event belongs to.
  ///   - hostname:  Reverse-DNS identifier for the app (e.g. `com.example.app`).
  ///   - authorization: Optional value sent verbatim as `Authorization`.
  ///                    Defaults to `nil`; umami `/api/send` is unauthenticated.
  ///   - allowInsecureHTTP: When `true`, an `http://` endpoint is accepted
  ///                        (useful for a local umami). Defaults to `false`.
  /// - Throws: ``UmamiConfigError`` when the endpoint URL cannot be used.
  public init(
    endpoint: URL,
    websiteId: String,
    hostname: String,
    appName: String = "-",
    displayName: String = "-",
    language: String = "en-US",
    screen: String = "-",
    os: String = "-",
    userAgent: String = "-",
    device: String = "-",
    id: String? = nil,
    userId: String? = nil,
    authorization: String? = nil,
    allowInsecureHTTP: Bool = false
  ) throws(UmamiConfigError) {
    let scheme = endpoint.scheme?.lowercased()
    switch scheme {
    case "https":
      self.scheme = "https"
    case "http":
      guard allowInsecureHTTP else { throw .insecureHTTPNotAllowed }
      self.scheme = "http"
    default:
      throw .unsupportedScheme(scheme)
    }

    guard let host = endpoint.host, !host.isEmpty else {
      throw .emptyHost
    }
    self.host = host

    self.websiteId = websiteId
    self.hostname = hostname
    self.appName = appName
    self.displayName = displayName
    self.language = language
    self.screen = screen
    self.os = os
    self.userAgent = userAgent
    self.device = device
    self.id = id
    self.userId = userId
    self.authorization = authorization
  }
}

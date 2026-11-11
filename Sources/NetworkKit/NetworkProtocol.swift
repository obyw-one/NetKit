//
//  NetworkProtocol.swift
//  NetworkKit
//
//  Extracted from WabiSabi — Created by Jeoffrey Thirot on 12/02/2024.
//

import CoreKit
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The platform-neutral request/response abstraction (builds on Linux).
///
/// The Combine publisher variant, `sendRequest(endpoint:type:)`, is NOT a
/// requirement any more: `Combine` is Apple-only, so it lives in the `NetKitApple`
/// product as an extension of this protocol (`import NetKitApple` to use it).
public protocol NetworkProtocol: Sendable {
    /// Build the `URLRequest` for an endpoint.
    /// - Throws: ``NetworkError/invalidURL(description:)`` when the endpoint does not form a
    ///   URL, ``NetworkError/bodyEncodingFailed(_:)`` when its body is not valid JSON. Nothing
    ///   is sent in either case: a request that silently lost its body is the failure this
    ///   signature exists to rule out.
    func createRequest(endPoint: EndPoint) throws(NetworkError) -> URLRequest

    func sendRequest<T: Decodable & Sendable>(endpoint: EndPoint) async throws -> T
    func sendRequest<T: Decodable>(endpoint: EndPoint, resultHandler: @escaping @Sendable (Result<T, NetworkError>) -> Void)
}

public extension NetworkProtocol {
    func createRequest(endPoint: EndPoint) throws(NetworkError) -> URLRequest {
        var urlComponents = URLComponents()
        urlComponents.scheme = endPoint.scheme
        urlComponents.host = endPoint.host
        urlComponents.port = endPoint.port
        urlComponents.path = endPoint.apiPath + endPoint.path
        if let queryParams = endPoint.queryParams {
            urlComponents.queryItems = Array(from: queryParams)
        }
        guard let url = urlComponents.url else {
            throw .invalidURL(description: "scheme '\(endPoint.scheme)', host '\(endPoint.host)', path '\(endPoint.apiPath + endPoint.path)'")
        }
        var request = URLRequest(url: url)
        request.httpMethod = endPoint.method.rawValue
        request.allHTTPHeaderFields = endPoint.header
        if let body = endPoint.body {
            request.httpBody = try Self.jsonBody(body)
        }
        return request
    }

    /// The JSON bytes of an endpoint body. `JSONSerialization` raises an Objective-C
    /// exception (a crash, not an error) for a value it cannot represent — a `Date`, a
    /// `NaN` — so validity is checked first and reported as a typed error.
    private static func jsonBody(_ body: [String: Any]) throws(NetworkError) -> Data {
        guard JSONSerialization.isValidJSONObject(body) else {
            throw .bodyEncodingFailed(BodyNotJSONRepresentable())
        }
        do {
            return try body.toJSON([])
        } catch {
            throw .bodyEncodingFailed(error)
        }
    }
}

/// The cause carried by ``NetworkError/bodyEncodingFailed(_:)`` when a body holds a value
/// JSON cannot represent (a `Date`, `NaN`, infinity, a non-string key, a custom type).
public struct BodyNotJSONRepresentable: Error, CustomStringConvertible, Sendable {
    public var description: String { "the body holds a value JSON cannot represent" }
}

public extension [URLQueryItem] {
    init(from dictionary: [String: Any]) {
        self = dictionary.map {
            switch $0.value {
            case let value as String:
                return [URLQueryItem(name: $0.key, value: value)]
            case let values as [String: Any]:
                let key = $0.key
                let subQuery = values.map {
                    let value: String = $0.value as? String ?? "-"
                    return URLQueryItem(name: "\(key)[\($0.key)]", value: value)
                }
                return subQuery
            case let values as any Collection:
                let key = $0.key
                let subQuery = values.map {
                    let value: String = $0 as? String ?? "-"
                    return URLQueryItem(name: "\(key)[]", value: value)
                }
                return subQuery
            default:
                return [URLQueryItem(name: $0.key, value: "-")]
            }
        }.flatMap { $0 }
    }
}

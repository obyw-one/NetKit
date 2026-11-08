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
    func createRequest(endPoint: EndPoint) -> URLRequest

    func sendRequest<T: Decodable & Sendable>(endpoint: EndPoint) async throws -> T
    func sendRequest<T: Decodable>(endpoint: EndPoint, resultHandler: @escaping @Sendable (Result<T, NetworkError>) -> Void)
}

public extension NetworkProtocol {
    func createRequest(endPoint: EndPoint) -> URLRequest {
        var urlComponents = URLComponents()
        urlComponents.scheme = endPoint.scheme
        urlComponents.host = endPoint.host
        urlComponents.port = endPoint.port
        urlComponents.path = endPoint.apiPath + endPoint.path
        if let queryParams = endPoint.queryParams {
            urlComponents.queryItems = Array(from: queryParams)
        }
        guard let url = urlComponents.url else {
            preconditionFailure("Failed to create url with your endPoint setup.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = endPoint.method.rawValue
        request.allHTTPHeaderFields = endPoint.header
        if let body = endPoint.body {
            request.httpBody = try? body.toJSON([])
        }
        return request
    }
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

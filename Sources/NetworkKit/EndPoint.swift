//
//  EndPoint.swift
//  NetworkKit
//
//  Extracted from WabiSabi — Created by Jeoffrey Thirot on 12/02/2024.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum RequestMethod: String, Sendable {
    case GET
    case POST
    case PUT
    case DELETE
    case PATCH
}

public protocol EndPoint: Sendable {
    var host: String { get }
    var port: Int? { get }
    var scheme: String { get }
    var apiPath: String { get }
    var apiFilePath: String { get }
    var path: String { get }
    var method: RequestMethod { get }
    var header: [String: String]? { get }
    var body: [String: Any]? { get }
    var queryParams: [String: Any]? { get }
}

extension EndPoint {
    public var scheme: String { "https" }
    public var port: Int? { nil }
    public var apiPath: String { "" }
    public var apiFilePath: String { "" }
}

// MARK: - Useful to manage url of endPoint

public protocol EndPointUrl {
    func getRequest() -> URLRequest
}

public protocol EndPointMediaUrl {
    func getMediaRequest() -> URLRequest
}

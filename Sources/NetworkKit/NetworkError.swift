//
//  NetworkError.swift
//  NetworkKit
//
//  Extracted from WabiSabi — Created by Jeoffrey Thirot on 12/02/2024.
//

import Foundation

public enum NetworkError: Error, CustomStringConvertible, Sendable {
    case requestFailed(description: String)
    case unexpectedStatusCode(_ statusCode: Int, headers: String? = nil)
    case invalidData
    case jsonParsingFailed(_ error: DecodingError)
    case wsError(description: String)
    /// The endpoint does not form a URL (for example a host with a path that does
    /// not start with `/`). Names the pieces; never the query, which may carry data.
    case invalidURL(description: String)
    /// The endpoint's body cannot be written as JSON. Nothing was sent.
    case bodyEncodingFailed(_ cause: any Error)
    case unknown(_ error: any Error)

    public var description: String {
        switch self {
        case .requestFailed(let description):           return "Request failed: \(description)"
        case .unexpectedStatusCode(let statusCode, _):  return "Invalid status code: \(statusCode)"
        case .invalidData:                              return "Invalid data"
        case .jsonParsingFailed(let error):             return "Failed to parse JSON: \(error.localizedDescription)"
        case .wsError(let description):                 return "WebSocket error: \(description)"
        case .invalidURL(let description):              return "Invalid URL: \(description)"
        case .bodyEncodingFailed(let cause):            return "Request body could not be encoded as JSON: \(cause)"
        case .unknown(let error):                       return "An unknown error occurred \(error.localizedDescription)"
        }
    }
}

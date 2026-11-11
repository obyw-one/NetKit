//
//  PocketError.swift
//  NetworkKit
//
//  Every HTTP, decoding or authentication failure of a PocketBase call is a
//  `PocketError`. The type exists because the older `NetworkError.unexpectedStatusCode`
//  keeps the status code and the headers and DROPS the body — and the body is
//  where PocketBase says what is wrong ("Failed to authenticate.", the field
//  that failed validation and why).
//

import Foundation

// MARK: - PocketErrorBody

/// PocketBase's own error body, exactly as the server sent it:
///
/// ```json
/// {"status":400,"message":"Failed to create record.",
///  "data":{"title":{"code":"validation_required","message":"Cannot be blank."}}}
/// ```
public struct PocketErrorBody: Codable, Equatable, Sendable {

    /// One failed field in `data`.
    public struct FieldError: Codable, Equatable, Sendable {
        public let code: String
        public let message: String

        public init(code: String, message: String) {
            self.code = code
            self.message = message
        }
    }

    public let status: Int
    public let message: String
    /// Per-field failures keyed by field name. Empty when the server named none
    /// (its `data` is `{}` or absent).
    public let data: [String: FieldError]

    public init(status: Int, message: String, data: [String: FieldError] = [:]) {
        self.status = status
        self.message = message
        self.data = data
    }

    private enum CodingKeys: String, CodingKey {
        case status, message, data
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(Int.self, forKey: .status)
        message = try container.decode(String.self, forKey: .message)
        data = try container.decodeIfPresent([String: FieldError].self, forKey: .data) ?? [:]
    }
}

// MARK: - PocketFailure

/// A non-2xx answer, kept whole.
public struct PocketFailure: Equatable, Sendable {
    /// `"METHOD /path"` of the call that failed. The query string is left out on
    /// purpose: a filter can carry personal data.
    public let endpoint: String
    public let status: Int
    /// PocketBase's own error body, when the answer carried one that decodes.
    public let body: PocketErrorBody?
    /// The answer verbatim. This is what a proxy's HTML page or a plain-text
    /// 502 leaves you with when ``body`` is `nil`.
    public let rawBody: Data

    public init(endpoint: String, status: Int, body: PocketErrorBody?, rawBody: Data) {
        self.endpoint = endpoint
        self.status = status
        self.body = body
        self.rawBody = rawBody
    }

    /// One line a log or a terminal can show: who answered what, and why.
    public var summary: String {
        guard let body else {
            return "\(endpoint) answered \(status) with a body that is not a PocketBase error (\(rawBody.count) bytes)"
        }
        var line = "\(endpoint) answered \(status): \(body.message)"
        if !body.data.isEmpty {
            let fields = body.data.keys.sorted().map { name in
                guard let field = body.data[name] else { return name }
                return "\(name) [\(field.code)] \(field.message)"
            }
            line += " — " + fields.joined(separator: "; ")
        }
        return line
    }
}

// MARK: - PocketError

/// The one error a ``PocketClientProtocol`` call throws.
///
/// Nothing here carries a token or a password: a failed login must not leave
/// the credential in a log line.
public enum PocketError: Error, Sendable, CustomStringConvertible, LocalizedError {
    /// The request could not be built or encoded, so nothing was sent.
    case invalidRequest(reason: String)
    /// The transport itself failed: offline, timeout, TLS, refused connection.
    case transport(any Error)
    /// The task was cancelled while the call was in flight.
    case cancelled
    /// The answer was not an HTTP response.
    case nonHTTPResponse
    /// The server rejected the credentials or the token: HTTP 401 or 403 on any
    /// call, or HTTP 400 on a login/refresh (PocketBase answers a wrong
    /// password with 400 "Failed to authenticate.").
    case authentication(PocketFailure)
    /// Any other non-2xx answer (not found, validation, rule refusal, server error).
    case http(PocketFailure)
    /// A 2xx answer that was expected to carry a body and carried none.
    case emptyResponse(status: Int)
    /// A 2xx answer whose body does not decode into the requested type.
    /// The body is deliberately not kept: on a login it is the token.
    case decoding(DecodingError, status: Int)

    /// The server's failure details, when there are any.
    public var failure: PocketFailure? {
        switch self {
        case .authentication(let failure), .http(let failure): return failure
        default: return nil
        }
    }

    /// PocketBase's own error body, when the server sent one.
    public var body: PocketErrorBody? { failure?.body }

    public var description: String {
        switch self {
        case .invalidRequest(let reason):
            return "PocketBase request not sent: \(reason)"
        case .transport(let error):
            return "PocketBase transport failed: \(error.localizedDescription)"
        case .cancelled:
            return "PocketBase call was cancelled."
        case .nonHTTPResponse:
            return "PocketBase answered with something that is not an HTTP response."
        case .authentication(let failure):
            return "PocketBase authentication failed — \(failure.summary)"
        case .http(let failure):
            return "PocketBase call failed — \(failure.summary)"
        case .emptyResponse(let status):
            return "PocketBase answered \(status) with an empty body where a record was expected."
        case .decoding(let error, let status):
            return "PocketBase answered \(status) but the body did not decode: \(error.localizedDescription)"
        }
    }

    public var errorDescription: String? { description }
}

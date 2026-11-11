//
//  MockPocketTransport.swift
//  NetworkKit
//
//  A scripted ``PocketTransport`` for tests of anything built on
//  ``PocketClient``. Replies are queued and consumed in order; every request is
//  recorded.
//
//  It is an actor, so it is `Sendable` without `@unchecked` and safe under
//  parallel tests. A request with no reply queued FAILS LOUDLY — a mock that
//  invented a default 200 would let a test pass on a call nobody scripted.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public actor MockPocketTransport: PocketTransport {

    /// What the next ``send(_:)`` does.
    public enum Reply: Sendable {
        /// An HTTP answer.
        case response(status: Int, body: Data)
        /// The transport itself fails (offline, timeout, ...).
        case failure(any Error)
        /// An answer that is not an HTTP response.
        case nonHTTP

        /// An HTTP answer whose body is the UTF-8 bytes of `json`.
        public static func json(status: Int = 200, _ json: String) -> Reply {
            .response(status: status, body: Data(json.utf8))
        }

        /// An HTTP answer with no body (204, for instance).
        public static func empty(status: Int = 204) -> Reply {
            .response(status: status, body: Data())
        }
    }

    /// What the mock itself can fail with. None of these is a scripted reply.
    public enum MockError: Error, CustomStringConvertible, Sendable {
        /// A request arrived and no reply was queued for it.
        case noReplyQueued(request: String)
        /// The request carries no URL, so no response can be addressed to it.
        case requestWithoutURL
        /// Foundation refused to build the HTTP response (an invalid status code).
        case unbuildableResponse(status: Int)

        public var description: String {
            switch self {
            case .noReplyQueued(let request): return "MockPocketTransport had no reply queued for \(request)"
            case .requestWithoutURL: return "MockPocketTransport was sent a request without a URL"
            case .unbuildableResponse(let status): return "MockPocketTransport could not build an HTTP \(status) response"
            }
        }
    }

    private var replies: [Reply]
    public private(set) var requests: [URLRequest] = []

    public init(replies: [Reply] = []) {
        self.replies = replies
    }

    /// Queue a reply after the ones already waiting.
    public func enqueue(_ reply: Reply) {
        replies.append(reply)
    }

    public func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard let url = request.url else { throw MockError.requestWithoutURL }
        guard !replies.isEmpty else {
            throw MockError.noReplyQueued(request: "\(request.httpMethod ?? "GET") \(url.path)")
        }
        switch replies.removeFirst() {
        case .failure(let error):
            throw error
        case .nonHTTP:
            return (Data(), URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil))
        case .response(let status, let body):
            guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)
            else { throw MockError.unbuildableResponse(status: status) }
            return (body, response)
        }
    }
}

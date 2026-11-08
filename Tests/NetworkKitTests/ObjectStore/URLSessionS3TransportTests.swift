import CoreKit
import Foundation
import Testing

@testable import NetKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Answers every request from a closure, so the transport is proven without a socket.
private class StubProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (HTTPURLResponse, Data))?
  static let lock = NSLock()

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func stopLoading() {}

  override func startLoading() {
    Self.lock.lock()
    let handler = Self.handler
    Self.lock.unlock()
    guard let handler else {
      client?.urlProtocol(self, didFailWithError: URLError(.unknown))
      return
    }
    let (response, data) = handler(request)
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }

  static func clear() {
    lock.lock()
    handler = nil
    lock.unlock()
  }

  static func install(_ handler: @escaping @Sendable (URLRequest) -> (HTTPURLResponse, Data)) {
    lock.lock()
    self.handler = handler
    lock.unlock()
  }
}

@Suite("URLSessionS3Transport", .serialized)
struct URLSessionS3TransportTests {

  private func makeSUT() -> URLSessionS3Transport {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubProtocol.self]
    return URLSessionS3Transport(session: URLSession(configuration: configuration))
  }

  private func request(method: String = "PUT", headers: [String: String] = [:], body: Data = Data()) throws -> S3Request {
    var components = URLComponents()
    components.scheme = "http"
    components.host = "store.example.test"
    components.port = 3900
    components.path = "/bucket/key"
    return S3Request(method: method, url: try #require(components.url), headers: headers, body: body)
  }

  @Test("sends method and headers, and lets URLSession derive Host from the signed URL")
  func sendsTheRequest() async throws {
    let seen = SeenRequest()
    StubProtocol.install { urlRequest in
      seen.set(urlRequest)
      return (HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!, Data())
    }
    let sut = makeSUT()
    _ = try await sut.send(request(headers: ["Host": "store.example.test:3900", "x-amz-date": "20261108T000000Z"], body: Data("hello".utf8)))
    let captured = try #require(seen.get())
    #expect(captured.httpMethod == "PUT")
    #expect(captured.value(forHTTPHeaderField: "x-amz-date") == "20261108T000000Z")
    // The stubbed URLProtocol sees the request URLSession built; the explicit Host header was not copied.
    #expect(captured.value(forHTTPHeaderField: "Host") == nil)
  }

  @Test("maps status, lower-cased headers and body into an S3Response")
  func mapsTheResponse() async throws {
    StubProtocol.install { urlRequest in
      (HTTPURLResponse(url: urlRequest.url!, statusCode: 404, httpVersion: nil, headerFields: ["ETag": "\"abc\"", "Content-Type": "application/xml"])!, Data("<Error/>".utf8))
    }
    let response = try await makeSUT().send(request(method: "GET"))
    #expect(response.status == 404)
    #expect(response.headers["etag"] == "\"abc\"")
    #expect(response.headers["content-type"] == "application/xml")
    #expect(response.body == Data("<Error/>".utf8))
  }

  @Test("a transport failure propagates to the caller")
  func propagatesFailure() async throws {
    StubProtocol.clear()
    await #expect(throws: (any Error).self) { _ = try await makeSUT().send(request(method: "GET")) }
  }
}

private final class SeenRequest: @unchecked Sendable {
  private let lock = NSLock()
  private var value: URLRequest?
  func set(_ request: URLRequest) { lock.lock(); value = request; lock.unlock() }
  func get() -> URLRequest? { lock.lock(); defer { lock.unlock() }; return value }
}

import CoreKit
import Foundation
import Testing

@testable import NetKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The transport's two ends are pure functions, so they are checked by their return
/// value; the loader in between is injected. No `URLProtocol` stub, no shared static
/// handler, no recorder (#20 review: "`@unchecked Sendable` & `NSLock()` => smell").
@Suite("URLSessionS3Transport")
struct URLSessionS3TransportTests {

  private static let signedURL: URL = {
    var components = URLComponents()
    components.scheme = "http"
    components.host = "store.example.test"
    components.port = 3900
    components.path = "/bucket/key"
    return components.url!
  }()

  private func request(method: String = "PUT", headers: [String: String] = [:], body: Data = Data()) -> S3Request {
    S3Request(method: method, url: Self.signedURL, headers: headers, body: body)
  }

  private func http(_ status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
    HTTPURLResponse(url: Self.signedURL, statusCode: status, httpVersion: nil, headerFields: headers)!
  }

  @Test("the URLRequest carries the signed URL, method, headers and body — never the Host header")
  func buildsTheRequest() {
    let built = URLSessionS3Transport.urlRequest(
      for: request(headers: ["Host": "store.example.test:3900", "x-amz-date": "20261108T000000Z"], body: Data("hello".utf8)))
    #expect(built.url == Self.signedURL)
    #expect(built.httpMethod == "PUT")
    #expect(built.value(forHTTPHeaderField: "x-amz-date") == "20261108T000000Z")
    // URLSession derives Host from the URL, which is what was signed.
    #expect(built.value(forHTTPHeaderField: "Host") == nil)
    #expect(built.httpBody == Data("hello".utf8))
  }

  @Test("an empty body is not sent")
  func emptyBodyIsAbsent() {
    #expect(URLSessionS3Transport.urlRequest(for: request(method: "GET")).httpBody == nil)
  }

  @Test("maps status, lower-cased headers and body into an S3Response")
  func mapsTheResponse() throws {
    let response = try URLSessionS3Transport.response(
      data: Data("<Error/>".utf8),
      response: http(404, headers: ["ETag": "\"abc\"", "Content-Type": "application/xml"]),
      operation: "GET")
    #expect(response.status == 404)
    #expect(response.headers["etag"] == "\"abc\"")
    #expect(response.headers["content-type"] == "application/xml")
    #expect(response.body == Data("<Error/>".utf8))
  }

  @Test("a non-HTTP answer is a malformed response for the operation")
  func nonHTTPIsMalformed() {
    let notHTTP = URLResponse(url: Self.signedURL, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
    #expect(throws: S3ObjectStoreError.malformedResponse(operation: "GET", detail: "the response is not HTTP")) {
      _ = try URLSessionS3Transport.response(data: Data(), response: notHTTP, operation: "GET")
    }
  }

  @Test("send loads the built request and returns the mapped answer")
  func sendRoundTrip() async throws {
    // The loader answers FROM the request it was given, so the assertion reads what
    // send passed it through the return value — nothing is recorded on the side.
    let sut = URLSessionS3Transport { urlRequest in
      let echo = HTTPURLResponse(
        url: urlRequest.url!, statusCode: 201, httpVersion: nil,
        headerFields: ["X-Seen-Method": urlRequest.httpMethod ?? "", "X-Seen-Date": urlRequest.value(forHTTPHeaderField: "x-amz-date") ?? ""])!
      return (urlRequest.httpBody ?? Data(), echo)
    }
    let response = try await sut.send(request(headers: ["x-amz-date": "20261108T000000Z"], body: Data("hello".utf8)))
    #expect(response.status == 201)
    #expect(response.headers["x-seen-method"] == "PUT")
    #expect(response.headers["x-seen-date"] == "20261108T000000Z")
    #expect(response.body == Data("hello".utf8))
  }

  @Test("a transport failure propagates to the caller")
  func propagatesFailure() async {
    let sut = URLSessionS3Transport { _ in throw URLError(.notConnectedToInternet) }
    await #expect(throws: URLError.self) { _ = try await sut.send(request(method: "GET")) }
  }
}

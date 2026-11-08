//
//  NetworkProtocol+Combine.swift
//  NetKitApple
//
//  The Combine publisher flavour of `NetworkProtocol.sendRequest`. It used to
//  be a protocol REQUIREMENT, which tied the platform-neutral protocol to an
//  Apple-only framework; it is now an extension available wherever Combine is
//  (`import NetKitApple`).
//

#if canImport(Combine)
import Combine
import Foundation
import NetKit

public extension NetworkProtocol {

    /// The publisher form of `sendRequest(endpoint:)`, over `URLSession`'s data task publisher.
    func sendRequest<T: Decodable>(endpoint: EndPoint, type: T.Type) -> AnyPublisher<T, NetworkError> {
        let urlRequest: URLRequest
        do {
            urlRequest = try createRequest(endPoint: endpoint)
        } catch {
            return Fail(error: error).eraseToAnyPublisher()
        }
        return URLSession.shared.dataTaskPublisher(for: urlRequest)
            .subscribe(on: DispatchQueue.global(qos: .background))
            .tryMap { data, response -> Data in
                guard let response = response as? HTTPURLResponse else {
                    throw NetworkError.requestFailed(description: "Unexpected HTTP answer")
                }
                guard 200..<400 ~= response.statusCode else {
                    throw NetworkError.unexpectedStatusCode(response.statusCode)
                }
                return data
            }
            .decode(type: T.self, decoder: JSONDecoder())
            .mapError { error -> NetworkError in
                if let error = error as? DecodingError {
                    return .jsonParsingFailed(error)
                } else if let error = error as? NetworkError {
                    return error
                } else {
                    return .unknown(error)
                }
            }
            .eraseToAnyPublisher()
    }
}

public extension MockNetworkService {

    /// The mock's publisher: the same captured request and the same configured
    /// answer as its `async` and closure forms, delivered synchronously.
    func sendRequest<T: Decodable>(endpoint: EndPoint, type: T.Type) -> AnyPublisher<T, NetworkError> {
        Deferred {
            let result: Result<T, NetworkError>
            do {
                result = .success(try self.response(for: endpoint))
            } catch let error as NetworkError {
                result = .failure(error)
            } catch {
                result = .failure(.unknown(error))
            }
            return result.publisher
        }
        .eraseToAnyPublisher()
    }
}
#endif

//
//  NetworkProtocol+Implementations.swift
//  NetworkKit
//
//  Extracted from WabiSabi — Created by Jeoffrey Thirot on 12/02/2024.
//

import Combine
import CoreKit
import Foundation
import os

public extension NetworkProtocol {
    func sendRequest<T: Decodable & Sendable>(endpoint: EndPoint) async throws -> T {
        let urlRequest = createRequest(endPoint: endpoint)
        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.requestFailed(description: "Unexpected HTTP answer")
        }
        guard 200..<400 ~= httpResponse.statusCode else {
            throw NetworkError.unexpectedStatusCode(httpResponse.statusCode, headers: httpResponse.allHeaderFields.map(String.init(describing:)).joined(separator: "\n"))
        }

        AppLog.network.debug("Request success: \(httpResponse.url?.debugDescription ?? "[no url]")")
        AppLog.network.debug("Response data: \((try? data.prettyJSON()) ?? "[Json invalid]")")

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom(decoder.pocketbaseDateDecodingStrategy())
            return try decoder.decode(T.self, from: data)
        } catch let error as DecodingError {
            throw NetworkError.jsonParsingFailed(error)
        } catch {
            throw NetworkError.unknown(error)
        }
    }

    func sendRequest<T: Decodable>(endpoint: EndPoint, type: T.Type) -> AnyPublisher<T, NetworkError> {
        let urlRequest = createRequest(endPoint: endpoint)
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

    func sendRequest<T: Decodable & Sendable>(endpoint: EndPoint, resultHandler: @escaping @Sendable (Result<T, NetworkError>) -> Void) {
        let urlRequest = createRequest(endPoint: endpoint)
        let urlTask = URLSession.shared.dataTask(with: urlRequest) { data, response, error in
            if let error {
                resultHandler(.failure(.unknown(error)))
                return
            }
            guard let response = response as? HTTPURLResponse else {
                resultHandler(.failure(.requestFailed(description: "Unexpected HTTP answer")))
                return
            }
            guard 200..<400 ~= response.statusCode else {
                resultHandler(.failure(.unexpectedStatusCode(response.statusCode)))
                return
            }
            guard let data = data else {
                resultHandler(.failure(.invalidData))
                return
            }

            do {
                let decodedResponse = try JSONDecoder().decode(T.self, from: data)
                resultHandler(.success(decodedResponse))
            } catch let error as DecodingError {
                resultHandler(.failure(NetworkError.jsonParsingFailed(error)))
            } catch {
                resultHandler(.failure(NetworkError.unknown(error)))
            }
        }
        urlTask.resume()
    }
}

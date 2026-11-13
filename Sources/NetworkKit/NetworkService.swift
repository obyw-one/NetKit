//
//  NetworkService.swift
//  NetworkKit
//
//  Extracted from WabiSabi — Created by Jeoffrey Thirot on 12/02/2024.
//

import Foundation

public final class NetworkService: NetworkProtocol {
    private let decoderFactory: (@Sendable () -> JSONDecoder)?

    /// The default service: responses decode with the PocketBase date strategy (unchanged).
    public init() {
        decoderFactory = nil
    }

    /// A service that decodes every response with a decoder built by `decoderFactory`
    /// (a fresh decoder per request, so nothing mutable is shared between requests).
    public init(decoderFactory: @escaping @Sendable () -> JSONDecoder) {
        self.decoderFactory = decoderFactory
    }

    /// A service that decodes every response like `decoder` does, e.g. with
    /// `keyDecodingStrategy = .convertFromSnakeCase`.
    ///
    /// `JSONDecoder` is not `Sendable`, so the service keeps a snapshot of its key, date, data
    /// and non-conforming-float strategies and builds a fresh decoder from it per request.
    /// `userInfo` is not carried over; use ``init(decoderFactory:)`` when you need it.
    public init(decoder: JSONDecoder) {
        let keys = decoder.keyDecodingStrategy
        let dates = decoder.dateDecodingStrategy
        let data = decoder.dataDecodingStrategy
        let floats = decoder.nonConformingFloatDecodingStrategy
        decoderFactory = {
            let copy = JSONDecoder()
            copy.keyDecodingStrategy = keys
            copy.dateDecodingStrategy = dates
            copy.dataDecodingStrategy = data
            copy.nonConformingFloatDecodingStrategy = floats
            return copy
        }
    }

    public func injectedDecoder() -> JSONDecoder? {
        decoderFactory?()
    }
}

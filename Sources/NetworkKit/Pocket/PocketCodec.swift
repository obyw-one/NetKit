//
//  PocketCodec.swift
//  NetworkKit
//
//  The one place a PocketBase JSON coder is configured.
//

import CoreKit
import Foundation

enum PocketCodec {

    /// Decoder for every PocketBase answer: dates go through the fleet strategy
    /// (`JSONDecoder.pocketbaseDateDecodingStrategy()`), nothing else is customised.
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(decoder.pocketbaseDateDecodingStrategy())
        return decoder
    }

    /// Encoder for every PocketBase request body: dates are written in the
    /// format the decoder reads (`2024-04-04 13:47:54.692Z`).
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(DateFormatter.pocketbase.string(from: date))
        }
        return encoder
    }
}

//
//  PocketListContainer.swift
//  NetworkKit
//
//  The paged-list envelope of `GET /api/collections/{collection}/records`:
//
//      {"page":1,"perPage":30,"totalPages":1,"totalItems":2,"items":[...]}
//

import Foundation

/// A page of records from a PocketBase list call.
///
/// Conformances are conditional on `Item`, so the container stays usable
/// wherever only `Decodable` is available while still being cacheable
/// (`Codable`), comparable (`Equatable`) and hashable when the record is:
/// - always `Decodable` when `Item: Decodable`
/// - `Encodable` only when `Item: Encodable`
/// - `Equatable` / `Hashable` when `Item` is, comparing every field
///
/// It is also a `MutableCollection` / `BidirectionalCollection` over `items`,
/// so a page iterates like the array it wraps.
///
/// `totalPages` and `totalItems` are `-1` when the list was requested with
/// ``PocketQuery/skipTotal``.
public struct PocketListContainer<Item: Decodable & Sendable>: MutableCollection, BidirectionalCollection, Sendable {
    public typealias Index = Int
    public typealias Element = Item

    public var page: Int
    public let perPage: Int
    public let totalPages: Int
    public let totalItems: Int

    public var items: [Item]

    enum CodingKeys: String, CodingKey, Sendable {
        case page, perPage, totalPages, totalItems, items
    }

    public init(page: Int = 1, perPage: Int = 30, totalPages: Int = 1, totalItems: Int = 0, items: [Item] = []) {
        self.page = page
        self.perPage = perPage
        self.totalPages = totalPages
        self.totalItems = totalItems
        self.items = items
    }
}

// MARK: - Decodable (always, when Item is)

extension PocketListContainer: Decodable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        page = try container.decode(Int.self, forKey: .page)
        perPage = try container.decode(Int.self, forKey: .perPage)
        totalPages = try container.decode(Int.self, forKey: .totalPages)
        totalItems = try container.decode(Int.self, forKey: .totalItems)
        items = try container.decode([Item].self, forKey: .items)
    }
}

// MARK: - Encodable (only when Item is)

extension PocketListContainer: Encodable where Item: Encodable {
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(page, forKey: .page)
        try container.encode(perPage, forKey: .perPage)
        try container.encode(totalPages, forKey: .totalPages)
        try container.encode(totalItems, forKey: .totalItems)
        try container.encode(items, forKey: .items)
    }
}

// MARK: - Equatable / Hashable (only when Item is)

extension PocketListContainer: Equatable where Item: Equatable {}
extension PocketListContainer: Hashable where Item: Hashable {}

// MARK: - MutableCollection

public extension PocketListContainer {
    var startIndex: Index { items.startIndex }
    var endIndex: Index { items.endIndex }

    subscript(position: Index) -> Element {
        get {
            precondition(position >= startIndex && position < endIndex, "Index out of range")
            return items[position]
        }
        set(newValue) {
            precondition(position >= startIndex && position < endIndex, "Index out of range")
            items[position] = newValue
        }
    }

    func index(after i: Index) -> Index {
        precondition(i < endIndex, "Index out of range")
        return items.index(after: i)
    }
}

// MARK: - BidirectionalCollection

public extension PocketListContainer {
    func index(before i: Index) -> Index {
        precondition(i > startIndex, "Index out of range")
        return items.index(before: i)
    }

    mutating func prepend(_ element: Element) {
        items.insert(element, at: 0)
    }

    mutating func append(_ element: Element) {
        items.append(element)
    }

    @discardableResult
    mutating func removeFirst() -> Element? {
        items.isEmpty ? nil : items.removeFirst()
    }

    @discardableResult
    mutating func removeLast() -> Element? {
        items.isEmpty ? nil : items.removeLast()
    }
}

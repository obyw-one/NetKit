//
//  PocketQuery.swift
//  NetworkKit
//
//  PocketBase's list parameters as one typed value. Every field is optional and
//  an absent field is simply not sent, so the server's own defaults apply
//  (page 1, perPage 30, no sort, no expand) — this type invents none.
//

import Foundation

/// The query of a records list.
///
/// ```swift
/// PocketQuery(perPage: 20, sort: "-created", filter: "done = false", expand: "author")
/// ```
///
/// Build a `filter` that contains a user-supplied value with
/// ``PocketFilter/literal(_:)``; string interpolation of a raw value is a
/// filter injection.
public struct PocketQuery: Equatable, Sendable {
    /// 1-based page.
    public var page: Int?
    /// Records per page.
    public var perPage: Int?
    /// Comma-separated fields, `-` for descending: `"-created,title"`.
    public var sort: String?
    /// A PocketBase filter expression: `"(status = 'open' && created > '2024-01-01')"`.
    public var filter: String?
    /// Comma-separated relation fields to expand: `"author,tags.owner"`.
    public var expand: String?
    /// Comma-separated fields to return: `"id,title,expand.author.name"`.
    public var fields: String?
    /// Skip the `COUNT` query. The container's `totalItems` and `totalPages`
    /// are then `-1`, which is PocketBase's own answer, not a bug.
    public var skipTotal: Bool

    public init(
        page: Int? = nil,
        perPage: Int? = nil,
        sort: String? = nil,
        filter: String? = nil,
        expand: String? = nil,
        fields: String? = nil,
        skipTotal: Bool = false
    ) {
        self.page = page
        self.perPage = perPage
        self.sort = sort
        self.filter = filter
        self.expand = expand
        self.fields = fields
        self.skipTotal = skipTotal
    }

    /// The parameters to send, in a fixed order, absent ones omitted.
    var items: [(name: String, value: String)] {
        var result: [(name: String, value: String)] = []
        if let page { result.append(("page", String(page))) }
        if let perPage { result.append(("perPage", String(perPage))) }
        if let sort { result.append(("sort", sort)) }
        if let filter { result.append(("filter", filter)) }
        if let expand { result.append(("expand", expand)) }
        if let fields { result.append(("fields", fields)) }
        if skipTotal { result.append(("skipTotal", "true")) }
        return result
    }
}

/// Helpers for building a PocketBase filter expression safely.
public enum PocketFilter {
    /// A string value as a PocketBase filter literal: single-quoted, with the
    /// single quote escaped as `\'`.
    ///
    /// ```swift
    /// let filter = "owner = \(try PocketFilter.literal(name)) && done = false"
    /// ```
    ///
    /// Interpolating a raw value instead is a filter injection: measured on a
    /// live server, `title = 'zzz' || title != ''` returns every record.
    ///
    /// A value containing a backslash is REFUSED. PocketBase changed what a
    /// backslash means inside a literal between releases (0.25.9 reads it
    /// verbatim and `\\` stays two characters; 0.40.6 reads `\\` as one
    /// backslash), so no single encoding is right for every server, and a
    /// backslash before the closing quote is how a literal is broken out of.
    ///
    /// - Throws: ``PocketError/invalidRequest(reason:)`` for a value with a backslash.
    public static func literal(_ value: String) throws(PocketError) -> String {
        guard !value.contains("\\") else {
            throw .invalidRequest(reason: "a filter value may not contain a backslash: PocketBase releases disagree on its meaning")
        }
        return "'" + value.replacingOccurrences(of: "'", with: "\\'") + "'"
    }
}

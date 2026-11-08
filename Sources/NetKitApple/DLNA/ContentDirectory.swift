#if canImport(Network)
import Foundation
import os

/// UPnP Content Directory Service — manages and serves media item metadata as DIDL-Lite XML.
public final class ContentDirectory: Sendable {
    // The items live in one value behind the platform's own Sendable lock
    // (not an `NSLock` beside a `var` under `@unchecked Sendable`), so the compiler
    // checks that nothing reads or writes them outside `withLock`.
    private let storage = OSAllocatedUnfairLock<[DLNAMediaItem]>(initialState: [])

    public init() {}

    // MARK: - Item management

    /// Replace all items in the directory.
    public func setItems(_ newItems: [DLNAMediaItem]) {
        storage.withLock { $0 = newItems }
    }

    /// Current number of items.
    public var count: Int {
        storage.withLock { $0.count }
    }

    /// `true` when the directory holds no item.
    public var isEmpty: Bool {
        storage.withLock { $0.isEmpty }
    }

    /// Get all items (snapshot).
    public var allItems: [DLNAMediaItem] {
        storage.withLock { $0 }
    }

    // MARK: - Browse

    /// Browse the content directory. ObjectID "0" returns the root container.
    public func browse(objectID: String, startIndex: Int = 0, requestedCount: Int = 0) -> BrowseResult {
        let snapshot = allItems

        if objectID == "0" {
            let total = snapshot.count
            let count = requestedCount > 0 ? min(requestedCount, total - startIndex) : total - startIndex
            let slice = Array(snapshot.dropFirst(startIndex).prefix(count))
            return BrowseResult(items: slice, totalMatches: total, numberReturned: slice.count)
        }

        // Single item lookup
        if let item = snapshot.first(where: { $0.id == objectID }) {
            return BrowseResult(items: [item], totalMatches: 1, numberReturned: 1)
        }

        return BrowseResult(items: [], totalMatches: 0, numberReturned: 0)
    }

    /// Search items by title substring (case-insensitive).
    public func search(query: String) -> [DLNAMediaItem] {
        let snapshot = allItems

        let lowered = query.lowercased()
        return snapshot.filter { $0.title.lowercased().contains(lowered) }
    }
}

// MARK: - BrowseResult

extension ContentDirectory {
    public struct BrowseResult: Sendable, Equatable {
        public let items: [DLNAMediaItem]
        public let totalMatches: Int
        public let numberReturned: Int
    }
}

// MARK: - DIDL-Lite XML Generation

extension ContentDirectory {
    /// Generate a DIDL-Lite XML document for the given items.
    /// - Parameter baseURL: The HTTP base URL for media file access (e.g. "http://192.168.1.10:8080").
    public static func didlLite(items: [DLNAMediaItem], baseURL: String) -> String {
        var xml = """
        <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"
                   xmlns:dc="http://purl.org/dc/elements/1.1/"
                   xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/"
                   xmlns:dlna="urn:schemas-dlna-org:metadata-1-0/">
        """

        for item in items {
            let escaped = xmlEscape(item.title)
            let creatorTag = item.creator.map { "    <dc:creator>\(xmlEscape($0))</dc:creator>\n" } ?? ""
            let durationAttr = item.formattedDuration.map { " duration=\"\($0)\"" } ?? ""
            let sizeAttr = item.fileSize.map { " size=\"\($0)\"" } ?? ""
            let resURL = "\(baseURL)/media/\(item.id)/\(xmlEscape(item.id)).\(item.fileExtension)"

            let thumbnailTag: String
            if item.thumbnailPath != nil {
                let thumbURL = "\(baseURL)/media/\(item.id)/thumbnail.jpg"
                thumbnailTag = "    <upnp:albumArtURI>\(thumbURL)</upnp:albumArtURI>\n"
            } else {
                thumbnailTag = ""
            }

            xml += """

              <item id="\(item.id)" parentID="0" restricted="1">
                <dc:title>\(escaped)</dc:title>
            \(creatorTag)\(thumbnailTag)    <upnp:class>object.item.videoItem</upnp:class>
                <res protocolInfo="http-get:*:\(item.mimeType):*"\(durationAttr)\(sizeAttr)>\(resURL)</res>
              </item>
            """
        }

        xml += "\n</DIDL-Lite>"
        return xml
    }

    /// Generate a SOAP Browse response envelope.
    public static func browseResponseEnvelope(didlLite: String, totalMatches: Int, numberReturned: Int) -> String {
        let escapedDidl = xmlEscape(didlLite)
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
                    s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:BrowseResponse xmlns:u="\(SSDPConstants.contentDirectoryType)">
              <Result>\(escapedDidl)</Result>
              <NumberReturned>\(numberReturned)</NumberReturned>
              <TotalMatches>\(totalMatches)</TotalMatches>
              <UpdateID>1</UpdateID>
            </u:BrowseResponse>
          </s:Body>
        </s:Envelope>
        """
    }

    static func xmlEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

// MARK: - UPnP Device Description XML

extension ContentDirectory {
    /// Generate the UPnP device description XML.
    public static func deviceDescriptionXML(
        friendlyName: String,
        uuid: String,
        baseURL: String
    ) -> String {
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <root xmlns="urn:schemas-upnp-org:device-1-0">
          <specVersion>
            <major>1</major>
            <minor>0</minor>
          </specVersion>
          <device>
            <deviceType>\(SSDPConstants.mediaServerType)</deviceType>
            <friendlyName>\(xmlEscape(friendlyName))</friendlyName>
            <manufacturer>BrainyTube</manufacturer>
            <modelName>BrainyTube Media Server</modelName>
            <modelNumber>1.0</modelNumber>
            <UDN>uuid:\(uuid)</UDN>
            <serviceList>
              <service>
                <serviceType>\(SSDPConstants.contentDirectoryType)</serviceType>
                <serviceId>urn:upnp-org:serviceId:ContentDirectory</serviceId>
                <controlURL>/ContentDirectory/control</controlURL>
                <eventSubURL>/ContentDirectory/event</eventSubURL>
                <SCPDURL>/ContentDirectory/scpd.xml</SCPDURL>
              </service>
            </serviceList>
          </device>
        </root>
        """
    }
}
#endif

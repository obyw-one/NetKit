#if canImport(Network)
import Foundation

/// SSDP multicast address and port.
public enum SSDPConstants {
    public static let multicastAddress = "239.255.255.250"
    public static let multicastPort: UInt16 = 1900
    public static let maxAge = 1800
    public static let mediaServerType = "urn:schemas-upnp-org:device:MediaServer:1"
    public static let contentDirectoryType = "urn:schemas-upnp-org:service:ContentDirectory:1"
    public static let rootDeviceType = "upnp:rootdevice"
}

/// Parsed SSDP message (NOTIFY or M-SEARCH response).
public struct SSDPMessage: Sendable, Equatable {
    public enum MessageType: Sendable, Equatable {
        case alive
        case byebye
        case searchResponse
        case search
    }

    public let type: MessageType
    public let usn: String
    public let location: String?
    public let searchTarget: String?
    public let server: String?
    public let maxAge: Int?

    public init(
        type: MessageType,
        usn: String,
        location: String? = nil,
        searchTarget: String? = nil,
        server: String? = nil,
        maxAge: Int? = nil
    ) {
        self.type = type
        self.usn = usn
        self.location = location
        self.searchTarget = searchTarget
        self.server = server
        self.maxAge = maxAge
    }
}

// MARK: - Parsing

extension SSDPMessage {
    /// Parse raw SSDP message bytes into a structured message.
    public static func parse(_ data: Data) -> SSDPMessage? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return parse(text)
    }

    /// Parse raw SSDP message string into a structured message.
    public static func parse(_ text: String) -> SSDPMessage? {
        let lines = text.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colonIndex].trimmingCharacters(in: .whitespaces).uppercased()
            let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let type: MessageType
        if firstLine.hasPrefix("NOTIFY") {
            let nts = headers["NTS"] ?? ""
            type = nts.contains("byebye") ? .byebye : .alive
        } else if firstLine.hasPrefix("HTTP/") {
            type = .searchResponse
        } else if firstLine.hasPrefix("M-SEARCH") {
            type = .search
        } else {
            return nil
        }

        let usn = headers["USN"] ?? ""
        guard !usn.isEmpty || type == .search else { return nil }

        let maxAge: Int? = {
            guard let cacheControl = headers["CACHE-CONTROL"] else { return nil }
            // Parse "max-age = 1800" or "max-age=1800"
            let parts = cacheControl.components(separatedBy: "=")
            guard parts.count == 2 else { return nil }
            return Int(parts[1].trimmingCharacters(in: .whitespaces))
        }()

        return SSDPMessage(
            type: type,
            usn: usn,
            location: headers["LOCATION"],
            searchTarget: headers["ST"] ?? headers["NT"],
            server: headers["SERVER"],
            maxAge: maxAge
        )
    }
}

// MARK: - Serialization

extension SSDPMessage {
    /// Build an SSDP NOTIFY alive message.
    public static func notifyAlive(
        location: String,
        usn: String,
        searchTarget: String,
        server: String,
        maxAge: Int = SSDPConstants.maxAge
    ) -> Data {
        let message = """
        NOTIFY * HTTP/1.1\r
        HOST: \(SSDPConstants.multicastAddress):\(SSDPConstants.multicastPort)\r
        CACHE-CONTROL: max-age=\(maxAge)\r
        LOCATION: \(location)\r
        NT: \(searchTarget)\r
        NTS: ssdp:alive\r
        SERVER: \(server)\r
        USN: \(usn)\r
        \r

        """
        return Data(message.utf8)
    }

    /// Build an SSDP NOTIFY byebye message.
    public static func notifyByebye(usn: String, searchTarget: String) -> Data {
        let message = """
        NOTIFY * HTTP/1.1\r
        HOST: \(SSDPConstants.multicastAddress):\(SSDPConstants.multicastPort)\r
        NT: \(searchTarget)\r
        NTS: ssdp:byebye\r
        USN: \(usn)\r
        \r

        """
        return Data(message.utf8)
    }

    /// Build an M-SEARCH request.
    public static func mSearch(
        searchTarget: String = "ssdp:all",
        maxWait: Int = 3
    ) -> Data {
        let message = """
        M-SEARCH * HTTP/1.1\r
        HOST: \(SSDPConstants.multicastAddress):\(SSDPConstants.multicastPort)\r
        MAN: "ssdp:discover"\r
        MX: \(maxWait)\r
        ST: \(searchTarget)\r
        \r

        """
        return Data(message.utf8)
    }

    /// Build an M-SEARCH response.
    public static func searchResponse(
        location: String,
        usn: String,
        searchTarget: String,
        server: String,
        maxAge: Int = SSDPConstants.maxAge
    ) -> Data {
        let message = """
        HTTP/1.1 200 OK\r
        CACHE-CONTROL: max-age=\(maxAge)\r
        LOCATION: \(location)\r
        ST: \(searchTarget)\r
        SERVER: \(server)\r
        USN: \(usn)\r
        \r

        """
        return Data(message.utf8)
    }
}
#endif

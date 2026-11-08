#if canImport(Network)
import Foundation
import Network
import os

/// A DLNA/UPnP Media Server that combines SSDP advertising with an HTTP file server.
///
/// Serves:
/// - `/description.xml` — UPnP device description
/// - `/ContentDirectory/control` — SOAP Browse/Search endpoint
/// - `/media/{id}/{filename}` — Video/thumbnail file serving with Range support
///
/// ```swift
/// let server = DLNAServer(friendlyName: "My Server")
/// server.contentDirectory.setItems(mediaItems)
/// try await server.start()
/// ```
public final class DLNAServer: Sendable {
    /// What changes after `init`: the Network listener, the SSDP helpers, the
    /// assigned port and the two callbacks. One value behind one lock, so
    /// `start()`, `stop()`, `port` and the setters are safe from any thread; the
    /// listener's callbacks (on `queue`) never call out while holding it.
    private struct State {
        var listener: NWListener?
        var advertiser: SSDPAdvertiser?
        var searchResponder: SSDPSearchResponder?
        var port: UInt16 = 0
        var onReady: (@Sendable (UInt16) -> Void)?
        var apiHandler: (@Sendable (_ method: String, _ path: String, _ body: Data?) -> (status: String, body: String)?)?
    }

    public let friendlyName: String
    public let uuid: String
    public let contentDirectory = ContentDirectory()

    private let queue = DispatchQueue(label: "net.netkit.dlna.server")
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Called when the server is ready and the port is assigned. Called on the
    /// server's queue, hence `@Sendable`.
    public var onReady: (@Sendable (UInt16) -> Void)? {
        get { state.withLock { $0.onReady } }
        set { state.withLock { $0.onReady = newValue } }
    }

    /// Custom API handler: (method, path, body) → (statusCode, responseBody)?
    /// Return nil to fall through to default routing.
    /// Set BEFORE calling start().
    public var apiHandler: (@Sendable (_ method: String, _ path: String, _ body: Data?) -> (status: String, body: String)?)? {
        get { state.withLock { $0.apiHandler } }
        set { state.withLock { $0.apiHandler = newValue } }
    }

    /// The port the server is listening on (available after `start()`).
    public var port: UInt16 { state.withLock { $0.port } }

    /// The base URL for this server (e.g., "http://192.168.1.10:8080").
    public var baseURL: String {
        let port = self.port
        guard let address = localIPAddress() else { return "http://localhost:\(port)" }
        return "http://\(address):\(port)"
    }

    public init(
        friendlyName: String = "BrainyTube",
        uuid: String = UUID().uuidString
    ) {
        self.friendlyName = friendlyName
        self.uuid = uuid
    }

    // MARK: - Lifecycle

    /// Start the DLNA server on a random available port and begin SSDP advertising.
    public func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        let nwListener = try NWListener(using: params, on: .any)
        let previous = state.withLock { state -> NWListener? in
            let old = state.listener
            state.listener = nwListener
            return old
        }
        previous?.cancel()

        nwListener.stateUpdateHandler = { [weak self] listenerState in
            guard let self else { return }
            if case .ready = listenerState, let port = nwListener.port?.rawValue {
                let onReady = self.state.withLock { state -> (@Sendable (UInt16) -> Void)? in
                    state.port = port
                    return state.onReady
                }
                self.startAdvertiser()
                onReady?(port)
            }
        }

        nwListener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        nwListener.start(queue: queue)
    }

    /// Stop the DLNA server and SSDP advertising.
    public func stop() {
        let (listener, advertiser, responder) = state.withLock { state in
            let taken = (state.listener, state.advertiser, state.searchResponder)
            state.listener = nil
            state.advertiser = nil
            state.searchResponder = nil
            return taken
        }
        advertiser?.stop()
        responder?.stop()
        listener?.cancel()
    }

    // MARK: - SSDP Advertising

    private func startAdvertiser() {
        let location = "\(baseURL)/description.xml"
        let usn = "uuid:\(uuid)::\(SSDPConstants.mediaServerType)"

        let adv = SSDPAdvertiser(location: location, usn: usn)
        let responder = SSDPSearchResponder(location: location, usn: usn)
        let previous = state.withLock { state -> (SSDPAdvertiser?, SSDPSearchResponder?) in
            let old = (state.advertiser, state.searchResponder)
            state.advertiser = adv
            state.searchResponder = responder
            return old
        }
        previous.0?.stop()
        previous.1?.stop()

        adv.start()
        // Also start listening for M-SEARCH queries so browsers can discover us
        responder.start()
    }

    // MARK: - HTTP Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHTTPRequest(on: connection)
    }

    private func receiveHTTPRequest(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, let request = String(data: data, encoding: .utf8) {
                self.routeRequest(request, rawData: data, on: connection)
            } else if isComplete || error != nil {
                connection.cancel()
            }
        }
    }

    private func routeRequest(_ request: String, rawData: Data, on connection: NWConnection) {
        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendResponse(connection: connection, status: "400 Bad Request", body: "Bad Request")
            return
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendResponse(connection: connection, status: "400 Bad Request", body: "Bad Request")
            return
        }

        let method = String(parts[0])
        let path = String(parts[1])
        let headers = Self.parseHeaders(lines.dropFirst())
        let handler = apiHandler

        switch (method, path) {
        case ("GET", "/description.xml"):
            handleDeviceDescription(connection: connection)

        case ("POST", "/ContentDirectory/control"):
            handleContentDirectoryControl(request: request, rawData: rawData, connection: connection)

        case ("GET", let p) where p.hasSuffix("/metadata.json") && p.hasPrefix("/media/"):
            handleMetadataRequest(path: p, connection: connection)

        case ("GET", let p) where p.hasPrefix("/media/"):
            handleMediaRequest(path: p, headers: headers, connection: connection)

        case ("HEAD", let p) where p.hasPrefix("/media/"):
            handleMediaRequest(path: p, headers: headers, connection: connection, headOnly: true)

        default:
            routeAPI(method: method, path: path, rawData: rawData, handler: handler, connection: connection)
        }
    }

    /// Everything that is not DLNA itself: the ping, the app's own API handler, else 404.
    private func routeAPI(
        method: String,
        path: String,
        rawData: Data,
        handler: (@Sendable (_ method: String, _ path: String, _ body: Data?) -> (status: String, body: String)?)?,
        connection: NWConnection
    ) {
        if method == "GET", path == "/api/ping" {
            sendResponse(connection: connection, status: "200 OK", contentType: "application/json", body: "{\"pong\":true,\"hasApiHandler\":\(handler != nil)}")
        } else if let result = handler?(method, path, Self.requestBody(in: rawData)) {
            // Custom API handler — the body is parsed from the raw HTTP data
            sendResponse(connection: connection, status: result.status, contentType: "application/json", body: result.body)
        } else {
            sendResponse(connection: connection, status: "404 Not Found", body: "Not Found")
        }
    }

    private static func parseHeaders(_ lines: ArraySlice<String>) -> [String: String] {
        var headers: [String: String] = [:]
        for line in lines {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colonIndex].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
        return headers
    }

    /// The bytes after the blank line that ends the HTTP headers, or nil when there are none.
    private static func requestBody(in rawData: Data) -> Data? {
        guard let range = rawData.firstRange(of: Data("\r\n\r\n".utf8)) else { return nil }
        let bodySlice = rawData[range.upperBound...]
        return bodySlice.isEmpty ? nil : Data(bodySlice)
    }

    // MARK: - Device Description

    private func handleDeviceDescription(connection: NWConnection) {
        let xml = ContentDirectory.deviceDescriptionXML(
            friendlyName: friendlyName,
            uuid: uuid,
            baseURL: baseURL
        )
        sendResponse(
            connection: connection,
            status: "200 OK",
            contentType: "text/xml; charset=\"utf-8\"",
            body: xml
        )
    }

    // MARK: - Content Directory Control

    private func handleContentDirectoryControl(request: String, rawData: Data, connection: NWConnection) {
        // Extract SOAP body — look for Browse action
        let requestStr = String(data: rawData, encoding: .utf8) ?? request

        // Parse ObjectID from SOAP — simple extraction
        let objectID = extractXMLValue(from: requestStr, tag: "ObjectID") ?? "0"
        let startIndex = Int(extractXMLValue(from: requestStr, tag: "StartingIndex") ?? "0") ?? 0
        let requestedCount = Int(extractXMLValue(from: requestStr, tag: "RequestedCount") ?? "0") ?? 0

        let result = contentDirectory.browse(objectID: objectID, startIndex: startIndex, requestedCount: requestedCount)
        let didl = ContentDirectory.didlLite(items: result.items, baseURL: baseURL)
        let envelope = ContentDirectory.browseResponseEnvelope(
            didlLite: didl,
            totalMatches: result.totalMatches,
            numberReturned: result.numberReturned
        )

        sendResponse(
            connection: connection,
            status: "200 OK",
            contentType: "text/xml; charset=\"utf-8\"",
            body: envelope
        )
    }

    // MARK: - Sidecar Metadata JSON

    private func handleMetadataRequest(path: String, connection: NWConnection) {
        // Path format: /media/{id}/metadata.json
        let components = path.split(separator: "/").map(String.init)
        guard components.count >= 3, components[0] == "media" else {
            sendResponse(connection: connection, status: "404 Not Found", body: "Not Found")
            return
        }

        let itemID = components[1]
        let items = contentDirectory.allItems
        guard let item = items.first(where: { $0.id == itemID }) else {
            sendResponse(connection: connection, status: "404 Not Found", body: "Item Not Found")
            return
        }

        // Build JSON with standard fields + app-specific metadata
        var json: [String: Any] = [
            "id": item.id,
            "title": item.title,
            "mimeType": item.mimeType,
            "resourceURL": "\(baseURL)/media/\(item.id)/\(item.id).\(item.fileExtension)",
        ]

        if let creator = item.creator { json["creator"] = creator }
        if let duration = item.duration { json["duration"] = duration }
        if let fileSize = item.fileSize { json["fileSize"] = fileSize }
        if item.thumbnailPath != nil {
            json["thumbnailURL"] = "\(baseURL)/media/\(item.id)/thumbnail.jpg"
        }

        // Merge app-specific metadata
        for (key, value) in item.metadata {
            json[key] = value
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]),
              let jsonString = String(data: jsonData, encoding: .utf8)
        else {
            sendResponse(connection: connection, status: "500 Internal Server Error", body: "JSON Error")
            return
        }

        sendResponse(
            connection: connection,
            status: "200 OK",
            contentType: "application/json",
            body: jsonString
        )
    }

    // MARK: - Media File Serving

    private func handleMediaRequest(path: String, headers: [String: String], connection: NWConnection, headOnly: Bool = false) {
        // Path format: /media/{id}/{filename}
        let components = path.split(separator: "/").map(String.init)
        guard components.count >= 3, components[0] == "media" else {
            sendResponse(connection: connection, status: "404 Not Found", body: "Not Found")
            return
        }

        let itemID = components[1]
        let filename = components[2]

        // Find the item
        let items = contentDirectory.allItems
        guard let item = items.first(where: { $0.id == itemID }) else {
            sendResponse(connection: connection, status: "404 Not Found", body: "Item Not Found")
            return
        }

        // Determine which file to serve
        let filePath: String
        if filename.hasPrefix("thumbnail") {
            guard let thumbPath = item.thumbnailPath else {
                sendResponse(connection: connection, status: "404 Not Found", body: "No Thumbnail")
                return
            }
            filePath = thumbPath
        } else {
            filePath = item.filePath
        }

        // Get file attributes
        let fm = FileManager.default
        guard fm.fileExists(atPath: filePath),
              let attrs = try? fm.attributesOfItem(atPath: filePath),
              let fileSize = attrs[.size] as? Int64
        else {
            sendResponse(connection: connection, status: "404 Not Found", body: "File Not Found")
            return
        }

        let mimeType = filename.hasPrefix("thumbnail") ? "image/jpeg" : item.mimeType

        // Parse Range header
        let target = MediaTarget(filePath: filePath, fileSize: fileSize, mimeType: mimeType)
        if let rangeHeader = headers["range"] {
            handleRangeRequest(target, rangeHeader: rangeHeader, connection: connection, headOnly: headOnly)
        } else {
            // Full file response
            let responseHeaders = """
            HTTP/1.1 200 OK\r
            Content-Type: \(mimeType)\r
            Content-Length: \(fileSize)\r
            Accept-Ranges: bytes\r
            Connection: close\r
            \r

            """

            let headerData = Data(responseHeaders.utf8)
            connection.send(content: headerData, completion: .contentProcessed { [weak self] _ in
                if !headOnly {
                    self?.sendFile(at: filePath, offset: 0, length: Int(fileSize), on: connection)
                } else {
                    connection.cancel()
                }
            })
        }
    }

    /// The file a media request resolved to.
    private struct MediaTarget {
        let filePath: String
        let fileSize: Int64
        let mimeType: String
    }

    private func handleRangeRequest(_ target: MediaTarget, rangeHeader: String, connection: NWConnection, headOnly: Bool) {
        let (filePath, fileSize, mimeType) = (target.filePath, target.fileSize, target.mimeType)
        // Parse "bytes=start-end" or "bytes=start-"
        guard rangeHeader.hasPrefix("bytes=") else {
            sendResponse(connection: connection, status: "416 Range Not Satisfiable", body: "Bad Range")
            return
        }

        let rangeSpec = String(rangeHeader.dropFirst(6))
        let parts = rangeSpec.split(separator: "-", maxSplits: 1)

        let start: Int64
        let end: Int64

        if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty {
            start = Int64(parts[0]) ?? 0
            end = min(Int64(parts[1]) ?? (fileSize - 1), fileSize - 1)
        } else if parts.count >= 1, !parts[0].isEmpty {
            start = Int64(parts[0]) ?? 0
            end = fileSize - 1
        } else if parts.count == 2, parts[0].isEmpty {
            // "bytes=-500" means last 500 bytes
            let suffix = Int64(parts[1]) ?? 0
            start = max(fileSize - suffix, 0)
            end = fileSize - 1
        } else {
            sendResponse(connection: connection, status: "416 Range Not Satisfiable", body: "Bad Range")
            return
        }

        guard start <= end, start < fileSize else {
            sendResponse(connection: connection, status: "416 Range Not Satisfiable", body: "Bad Range")
            return
        }

        let contentLength = end - start + 1
        let responseHeaders = """
        HTTP/1.1 206 Partial Content\r
        Content-Type: \(mimeType)\r
        Content-Length: \(contentLength)\r
        Content-Range: bytes \(start)-\(end)/\(fileSize)\r
        Accept-Ranges: bytes\r
        Connection: close\r
        \r

        """

        let headerData = Data(responseHeaders.utf8)
        connection.send(content: headerData, completion: .contentProcessed { [weak self] _ in
            if !headOnly {
                self?.sendFile(at: filePath, offset: Int(start), length: Int(contentLength), on: connection)
            } else {
                connection.cancel()
            }
        })
    }

    private func sendFile(at path: String, offset: Int, length: Int, on connection: NWConnection) {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            connection.cancel()
            return
        }

        handle.seek(toFileOffset: UInt64(offset))
        Self.sendChunk(from: handle, remaining: length, on: connection)
    }

    /// Send the next 64 KiB and, once the connection has taken it, the one after.
    /// The count still to send travels BY VALUE in the completion handler, so no
    /// shared mutable state exists to guard: each chunk's handler is the only
    /// owner of "what is left".
    private static func sendChunk(from handle: FileHandle, remaining: Int, on connection: NWConnection) {
        let toRead = min(65536, remaining)
        guard toRead > 0 else {
            try? handle.close()
            connection.cancel()
            return
        }

        let data = handle.readData(ofLength: toRead)
        guard !data.isEmpty else {
            try? handle.close()
            connection.cancel()
            return
        }

        let left = remaining - data.count
        let isLast = left <= 0

        connection.send(content: data, isComplete: isLast, completion: .contentProcessed { error in
            if error != nil || isLast {
                try? handle.close()
                if isLast { connection.cancel() }
            } else {
                sendChunk(from: handle, remaining: left, on: connection)
            }
        })
    }

    // MARK: - HTTP Response

    private func sendResponse(
        connection: NWConnection,
        status: String,
        contentType: String = "text/plain",
        body: String
    ) {
        let bodyData = Data(body.utf8)
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: \(contentType)\r
        Content-Length: \(bodyData.count)\r
        Connection: close\r
        \r

        """
        var data = Data(response.utf8)
        data.append(bodyData)

        connection.send(content: data, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Helpers

    private func extractXMLValue(from xml: String, tag: String) -> String? {
        guard let startRange = xml.range(of: "<\(tag)>"),
              let endRange = xml.range(of: "</\(tag)>")
        else { return nil }
        let valueStart = startRange.upperBound
        let valueEnd = endRange.lowerBound
        guard valueStart < valueEnd else { return nil }
        return String(xml[valueStart..<valueEnd])
    }

    private func localIPAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var result: String?
        var current = ifaddr
        while let ptr = current {
            let addr = ptr.pointee
            let family = addr.ifa_addr.pointee.sa_family
            if family == UInt8(AF_INET) {
                let name = String(cString: addr.ifa_name)
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    let addrLen = socklen_t(addr.ifa_addr.pointee.sa_len)
                    if getnameinfo(addr.ifa_addr, addrLen, &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                        result = hostname.withUnsafeBufferPointer { buffer in buffer.baseAddress.flatMap { String(validatingCString: $0) } }
                        break
                    }
                }
            }
            current = addr.ifa_next
        }
        return result
    }
}
#endif

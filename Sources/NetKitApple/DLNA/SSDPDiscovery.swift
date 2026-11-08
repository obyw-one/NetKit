#if canImport(Network)
import Foundation
import Network
import os

/// Delegate for SSDP device discovery events.
public protocol SSDPDelegate: AnyObject, Sendable {
    func ssdpDidDiscover(message: SSDPMessage)
    func ssdpDidLose(usn: String)
}

// MARK: - SSDPAdvertiser

/// Advertises a UPnP device on the local network via SSDP NOTIFY multicast.
///
/// `Sendable` without `@unchecked`: the connection and the timer are the only
/// mutable state, they live in one value behind an `OSAllocatedUnfairLock`, and
/// `start()` / `stop()` may be called from any thread. The Network framework's
/// callbacks run on `queue`; they never hold the lock while calling out.
public final class SSDPAdvertiser: Sendable {
    private struct State {
        var connection: NWConnection?
        var aliveTimer: DispatchSourceTimer?
    }

    private let location: String
    private let usn: String
    private let server: String
    private let deviceType: String

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let queue = DispatchQueue(label: "net.netkit.ssdp.advertiser")

    public init(
        location: String,
        usn: String,
        server: String = "macOS/1.0 UPnP/1.0 BrainyTube/1.0",
        deviceType: String = SSDPConstants.mediaServerType
    ) {
        self.location = location
        self.usn = usn
        self.server = server
        self.deviceType = deviceType
    }

    /// Start advertising on the SSDP multicast group. Sends an initial NOTIFY alive
    /// and repeats at the given interval.
    public func start(interval: TimeInterval = 600) {
        let host = NWEndpoint.Host(SSDPConstants.multicastAddress)
        let port = NWEndpoint.Port(rawValue: SSDPConstants.multicastPort)!

        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true

        let conn = NWConnection(host: host, port: port, using: params)
        let previous = state.withLock { state -> NWConnection? in
            let old = state.connection
            state.connection = conn
            return old
        }
        previous?.cancel()

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .ready = state {
                self.sendAlive()
                self.scheduleAliveTimer(interval: interval)
            }
        }
        conn.start(queue: queue)
    }

    /// Stop advertising — sends NOTIFY byebye and tears down the connection.
    public func stop() {
        let (timer, conn) = state.withLock { state -> (DispatchSourceTimer?, NWConnection?) in
            let taken = (state.aliveTimer, state.connection)
            state.aliveTimer = nil
            state.connection = nil
            return taken
        }
        timer?.cancel()

        if let conn, conn.state == .ready {
            let byebye = SSDPMessage.notifyByebye(usn: usn, searchTarget: deviceType)
            conn.send(content: byebye, completion: .contentProcessed { _ in })
        }
        conn?.cancel()
    }

    private func sendAlive() {
        guard let conn = state.withLock({ $0.connection }) else { return }
        let data = SSDPMessage.notifyAlive(
            location: location,
            usn: usn,
            searchTarget: deviceType,
            server: server
        )
        conn.send(content: data, completion: .contentProcessed { _ in })

        // Also advertise root device
        let rootData = SSDPMessage.notifyAlive(
            location: location,
            usn: usn,
            searchTarget: SSDPConstants.rootDeviceType,
            server: server
        )
        conn.send(content: rootData, completion: .contentProcessed { _ in })
    }

    private func scheduleAliveTimer(interval: TimeInterval) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.sendAlive()
        }
        timer.resume()
        let previous = state.withLock { state -> DispatchSourceTimer? in
            let old = state.aliveTimer
            state.aliveTimer = timer
            return old
        }
        previous?.cancel()
    }
}

// MARK: - SSDPSearchResponder

/// Listens for M-SEARCH requests on the SSDP multicast group and replies with unicast responses.
/// Used by `DLNAServer` so that browsers (iPad/VLC/etc.) can discover the server on demand.
public final class SSDPSearchResponder: Sendable {
    private let location: String
    private let usn: String
    private let server: String
    private let deviceType: String

    private let listener = OSAllocatedUnfairLock<NWListener?>(initialState: nil)
    private let queue = DispatchQueue(label: "net.netkit.ssdp.searchResponder")

    public init(
        location: String,
        usn: String,
        server: String = "macOS/1.0 UPnP/1.0 BrainyTube/1.0",
        deviceType: String = SSDPConstants.mediaServerType
    ) {
        self.location = location
        self.usn = usn
        self.server = server
        self.deviceType = deviceType
    }

    /// Start listening for M-SEARCH queries on the SSDP multicast port.
    public func start() {
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true

        guard let newListener = try? NWListener(using: params, on: NWEndpoint.Port(rawValue: SSDPConstants.multicastPort)!) else {
            return
        }
        let previous = listener.withLock { current -> NWListener? in
            let old = current
            current = newListener
            return old
        }
        previous?.cancel()

        newListener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        newListener.start(queue: queue)
    }

    /// Stop listening.
    public func stop() {
        let current = listener.withLock { current -> NWListener? in
            let old = current
            current = nil
            return old
        }
        current?.cancel()
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveMessage(on: connection)
    }

    private func receiveMessage(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self, let data, error == nil else { return }

            if let message = SSDPMessage.parse(data), message.type == .search {
                // Check if the search target matches our device type or ssdp:all
                let st = message.searchTarget ?? ""
                if st == "ssdp:all" || st == self.deviceType || st == SSDPConstants.rootDeviceType {
                    let response = SSDPMessage.searchResponse(
                        location: self.location,
                        usn: self.usn,
                        searchTarget: self.deviceType,
                        server: self.server
                    )
                    connection.send(content: response, completion: .contentProcessed { _ in })
                }
            }

            self.receiveMessage(on: connection)
        }
    }
}

// MARK: - SSDPBrowser

/// Discovers UPnP devices on the local network by sending M-SEARCH and listening for responses.
///
/// Uses NWConnectionGroup to join the SSDP multicast group (239.255.255.250:1900)
/// so we receive both NOTIFY announcements AND unicast M-SEARCH responses.
/// NWListener alone cannot receive multicast traffic.
///
/// `Sendable` without `@unchecked`: the group, the search connection, the set of
/// known USNs and the delegate are one value behind an `OSAllocatedUnfairLock`.
/// The delegate is called OUTSIDE the lock, on `queue`.
public final class SSDPBrowser: Sendable {
    private struct State {
        var multicastGroup: NWConnectionGroup?
        var searchConnection: NWConnection?
        var discoveredUSNs: Set<String> = []
        weak var delegate: SSDPDelegate?
    }

    private let searchTarget: String
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let queue = DispatchQueue(label: "net.netkit.ssdp.browser")

    /// Notified of discovered and lost devices, on the browser's queue.
    public var delegate: SSDPDelegate? {
        get { state.withLock { $0.delegate } }
        set { state.withLock { $0.delegate = newValue } }
    }

    public init(searchTarget: String = SSDPConstants.mediaServerType) {
        self.searchTarget = searchTarget
    }

    /// Start browsing — joins SSDP multicast group and sends M-SEARCH.
    public func start() {
        joinMulticastGroup()
        sendSearch()
    }

    /// Stop browsing.
    public func stop() {
        let (group, conn) = state.withLock { state -> (NWConnectionGroup?, NWConnection?) in
            let taken = (state.multicastGroup, state.searchConnection)
            state.multicastGroup = nil
            state.searchConnection = nil
            state.discoveredUSNs.removeAll()
            return taken
        }
        group?.cancel()
        conn?.cancel()
    }

    /// Send an M-SEARCH request to discover devices.
    /// Responses arrive as unicast on the same connection.
    public func sendSearch() {
        let host = NWEndpoint.Host(SSDPConstants.multicastAddress)
        let port = NWEndpoint.Port(rawValue: SSDPConstants.multicastPort)!

        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true

        let conn = NWConnection(host: host, port: port, using: params)
        // Close the previous search connection
        let previous = state.withLock { state -> NWConnection? in
            let old = state.searchConnection
            state.searchConnection = conn
            return old
        }
        previous?.cancel()

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .ready = state {
                let data = SSDPMessage.mSearch(searchTarget: self.searchTarget)
                conn.send(content: data, completion: .contentProcessed { _ in })
                // Listen for unicast responses on this connection
                self.receiveSearchResponses(on: conn)
            }
        }
        conn.start(queue: queue)
    }

    /// Listen for unicast search responses on the M-SEARCH connection.
    private func receiveSearchResponses(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self, let data, error == nil else { return }
            self.handleSSDPData(data)
            // Keep listening for more responses
            self.receiveSearchResponses(on: connection)
        }
    }

    /// Join the SSDP multicast group to receive NOTIFY announcements.
    private func joinMulticastGroup() {
        let multicastEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(SSDPConstants.multicastAddress),
            port: NWEndpoint.Port(rawValue: SSDPConstants.multicastPort)!
        )

        guard let groupDesc = try? NWMulticastGroup(for: [multicastEndpoint]) else { return }
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true

        let group = NWConnectionGroup(with: groupDesc, using: params)
        let previous = state.withLock { state -> NWConnectionGroup? in
            let old = state.multicastGroup
            state.multicastGroup = group
            return old
        }
        previous?.cancel()

        group.setReceiveHandler(maximumMessageSize: 65536, rejectOversizedMessages: true) { [weak self] _, data, _ in
            guard let self, let data else { return }
            self.handleSSDPData(data)
        }

        group.stateUpdateHandler = { _ in
            // NWConnectionGroup state changes — no action needed
        }

        group.start(queue: queue)
    }

    private func handleSSDPData(_ data: Data) {
        guard let message = SSDPMessage.parse(data) else { return }

        queue.async { [weak self] in
            guard let self else { return }
            switch message.type {
            case .alive, .searchResponse:
                let (isNew, delegate) = self.state.withLock { state in
                    (state.discoveredUSNs.insert(message.usn).inserted, state.delegate)
                }
                if isNew {
                    delegate?.ssdpDidDiscover(message: message)
                }
            case .byebye:
                let delegate = self.state.withLock { state -> SSDPDelegate? in
                    state.discoveredUSNs.remove(message.usn)
                    return state.delegate
                }
                delegate?.ssdpDidLose(usn: message.usn)
            case .search:
                break // We don't respond to searches as a browser
            }
        }
    }
}
#endif

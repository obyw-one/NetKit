//
//  WebSocketClient.swift
//  NetKit
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Actor-based WebSocket client with automatic reconnection.
///
/// Exposes an `AsyncStream<WebSocketMessage>` for incoming messages.
/// Reconnects automatically on unexpected disconnection up to `maxReconnectAttempts`
/// with exponential back-off.
///
/// ```swift
/// let ws = WebSocketClient(url: URL(string: "wss://example.com/ws")!)
/// for await message in await ws.connect() {
///     print(message)
/// }
/// ```
public actor WebSocketClient {
    private let url: URL
    private let session: URLSession
    private let maxReconnectAttempts: Int
    private let reconnectDelay: TimeInterval

    private var task: URLSessionWebSocketTask?
    private var continuation: AsyncStream<WebSocketMessage>.Continuation?
    private var reconnectAttempt = 0
    private var isIntentionalDisconnect = false

    public private(set) var state: WebSocketState = .disconnected

    /// Creates a WebSocket client targeting the given URL.
    /// - Parameters:
    ///   - url: The WebSocket endpoint URL.
    ///   - session: The `URLSession` for the underlying task (defaults to `.shared`).
    ///   - maxReconnectAttempts: Maximum automatic reconnection attempts before giving up.
    ///   - reconnectDelay: Base delay between reconnection attempts (multiplied by attempt number).
    public init(
        url: URL,
        session: URLSession = .shared,
        maxReconnectAttempts: Int = 5,
        reconnectDelay: TimeInterval = 2.0
    ) {
        self.url = url
        self.session = session
        self.maxReconnectAttempts = maxReconnectAttempts
        self.reconnectDelay = reconnectDelay
    }

    // MARK: - Connect

    /// Opens the WebSocket connection and returns a stream of incoming messages.
    ///
    /// Cancelling iteration on the returned stream automatically disconnects.
    public func connect() -> AsyncStream<WebSocketMessage> {
        isIntentionalDisconnect = false
        reconnectAttempt = 0

        let stream = AsyncStream<WebSocketMessage> { continuation in
            self.continuation = continuation
            continuation.onTermination = { @Sendable _ in
                Task { await self.disconnect() }
            }
        }

        startTask()
        return stream
    }

    // MARK: - Disconnect

    /// Gracefully closes the WebSocket connection and finishes the message stream.
    public func disconnect() {
        isIntentionalDisconnect = true
        state = .disconnected
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        continuation?.finish()
        continuation = nil
    }

    // MARK: - Send

    /// Sends a message through the open WebSocket connection.
    /// - Throws: ``NetworkError/wsError(description:)`` if the socket is not connected.
    public func send(_ message: WebSocketMessage) async throws {
        guard let task, state == .connected else {
            throw NetworkError.wsError(description: "Not connected")
        }
        switch message {
        case .text(let string):
            try await task.send(.string(string))
        case .data(let data):
            try await task.send(.data(data))
        }
    }

    /// Convenience: sends a text string through the WebSocket.
    public func send(text: String) async throws {
        try await send(.text(text))
    }

    /// Convenience: sends raw data through the WebSocket.
    public func send(data: Data) async throws {
        try await send(.data(data))
    }

    // MARK: - Private

    private func startTask() {
        state = reconnectAttempt > 0 ? .reconnecting(attempt: reconnectAttempt) : .connecting
        let wsTask = session.webSocketTask(with: url)
        self.task = wsTask
        wsTask.resume()
        state = .connected
        receiveLoop()
    }

    private func receiveLoop() {
        guard let task else { return }
        task.receive { [weak self] result in
            Task { [weak self] in
                guard let self else { return }
                await self.handleReceive(result)
            }
        }
    }

    private func handleReceive(_ result: Result<URLSessionWebSocketTask.Message, any Error>) {
        switch result {
        case .success(let message):
            reconnectAttempt = 0
            switch message {
            case .string(let text):
                continuation?.yield(.text(text))
            case .data(let data):
                continuation?.yield(.data(data))
            @unknown default:
                break
            }
            receiveLoop()

        case .failure:
            guard !isIntentionalDisconnect else { return }
            task = nil
            state = .disconnected

            if reconnectAttempt < maxReconnectAttempts {
                reconnectAttempt += 1
                let delay = reconnectDelay * Double(reconnectAttempt)
                Task {
                    try? await Task.sleep(for: .seconds(delay))
                    guard !self.isIntentionalDisconnect else { return }
                    self.startTask()
                }
            } else {
                continuation?.finish()
                continuation = nil
            }
        }
    }
}

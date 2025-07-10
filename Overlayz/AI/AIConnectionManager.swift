//
//  AIConnectionManager.swift
//  Overlayz
//
//  Created by AI Assistant on 5/15/25.
//

import Foundation
import Combine

#if canImport(UIKit)
import UIKit
#endif

@available(iOS 15.0, macOS 12.0, *)
extension URLSessionWebSocketTask {
    /// Sends a ping and suspends until a pong is received or an error occurs.
    func sendPing() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // The built-in sendPing API; calls the closure when pong arrives or on error
            self.sendPing { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}


// MARK: - Models
struct AIMessage: Codable {
    let role: String
    let content: String
    let metadata: AIMessageMetadata?
    
    init(role: String, content: String, metadata: AIMessageMetadata? = nil) {
        self.role = role
        self.content = content
        self.metadata = metadata
    }
}

struct AIMessageMetadata: Codable {
    let ocrText: String?
    let selectedText: String?
    
    init(ocrText: String? = nil, selectedText: String? = nil) {
        self.ocrText = ocrText
        self.selectedText = selectedText
    }
}

struct AIRequest: Codable {
    let messages: [AIMessage]
    let imageBytes: String? // Base64 encoded image data
    let smarterAnalysisEnabled: Bool
    
    init(messages: [AIMessage], imageBytes: String? = nil, smarterAnalysisEnabled: Bool = false) {
        self.messages = messages
        self.imageBytes = imageBytes
        self.smarterAnalysisEnabled = smarterAnalysisEnabled
    }
}

struct AIResponse: Codable {
    let content: String
    let isComplete: Bool
}

struct MessageData: Identifiable, Equatable{
    var topId = UUID()
    var id = UUID()
    var bottomId = UUID()
    var message = ""
    var isUser: Bool = false
}

// MARK: - Connection Manager
class AIConnectionManager: ObservableObject {
    // Singleton
    static let shared = AIConnectionManager()
    
    @Published var lastMessages = [MessageData]()

    // Publishers
    @Published var messageStream: String = ""
    @Published var isConnected: Bool = false
    @Published var isReceiving: Bool = false
    
    // Context manager
    private let contextManager = AIContextManager.shared

    // WebSocket and session
    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    // private var connectionURL = URL(string: "ws://localhost:8000/horizon/assist/chat-ws")!
    private var connectionURL = URL(string: "wss://itzerhypergalaxy.online/horizon/assist/chat-ws")!
    
    // Background connection management
    private var shouldMaintainConnection: Bool = true
    #if canImport(UIKit)
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
    #endif
    private var reconnectionAttempts: Int = 0
    private let maxReconnectionAttempts: Int = 10
    private var reconnectionDelay: TimeInterval = 1.0
    
    // Message history
    private var messageHistory: [AIMessage] = []
    
    // Tasks for connection
    private var receiveTask: Task<Void, Error>?
    private var pingTask: Task<Void, Error>?
    private var connectionMonitorTask: Task<Void, Error>?

    private init() {
        setupSession()
        setupBackgroundHandling()
        
        // Auto-connect on initialization
        Task {
            try await connect()
        }
    }
    
    // MARK: - Setup methods
    
    func setupSession() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        session = URLSession(configuration: config)
    }
    
    private func setupBackgroundHandling() {
        #if canImport(UIKit)
        // Monitor app state changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        #endif
    }
    
    #if canImport(UIKit)
    @objc private func appDidEnterBackground() {
        // Request background time to maintain connection
        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(withName: "AIWebSocketConnection") {
            // Called when background time is about to expire
            self.endBackgroundTask()
        }
    }
    
    @objc private func appWillEnterForeground() {
        endBackgroundTask()
        
        // Ensure connection is still active when returning to foreground
        if shouldMaintainConnection && !isConnected {
            Task {
                try await connect()
            }
        }
    }
    
    private func endBackgroundTask() {
        if backgroundTaskIdentifier != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
            backgroundTaskIdentifier = .invalid
        }
    }
    #endif
    
    // MARK: - Connection methods
    
    func connect() async throws {
        guard let session = session, webSocket == nil, shouldMaintainConnection else { return }
        
        webSocket = session.webSocketTask(with: connectionURL)
        webSocket?.resume()
        
        await MainActor.run {
            isConnected = true
        }
        
        // Reset reconnection attempts on successful connection
        reconnectionAttempts = 0
        reconnectionDelay = 1.0
        
        startPingTask()
        startReceiveTask()
        startConnectionMonitorTask()
    }
    
    private func startPingTask() {
        pingTask = Task {
            while !Task.isCancelled, webSocket != nil, shouldMaintainConnection {
                do {
                    try await ping()
                    try await Task.sleep(nanoseconds: 1_000_000_000 * 30) // 30 seconds
                } catch {
                    print("Ping failed: \(error)")
                    break
                }
            }
        }
    }
    
    private func startReceiveTask() {
        receiveTask = Task {
            do {
                while !Task.isCancelled, webSocket != nil, shouldMaintainConnection {
                    guard let task = webSocket else { break }
                    
                    let message = try await task.receive()
                    
                    switch message {
                    case .data(let data):
                        handleReceivedData(data)
                    case .string(let text):
                        handleReceivedText(text)
                    @unknown default:
                        break
                    }
                }
            } catch {
                if !Task.isCancelled && shouldMaintainConnection {
                    print("Receive task error: \(error)")
                    await handleConnectionError(error)
                }
            }
        }
    }
    
    private func startConnectionMonitorTask() {
        connectionMonitorTask = Task {
            while !Task.isCancelled, shouldMaintainConnection {
                try await Task.sleep(nanoseconds: 1_000_000_000 * 10) // Check every 10 seconds
                
                if shouldMaintainConnection && !isConnected {
                    do {
                        try await reconnect()
                    } catch {
                        print("Connection monitor reconnect failed: \(error)")
                    }
                }
            }
        }
    }
    
    /// Gracefully disconnect (only use when intentionally shutting down)
    func gracefulDisconnect() async {
        shouldMaintainConnection = false
        await disconnect()
        #if canImport(UIKit)
        endBackgroundTask()
        #endif
    }
    
    private func disconnect() async {
        pingTask?.cancel()
        receiveTask?.cancel()
        connectionMonitorTask?.cancel()
        
        try? await Task.sleep(for: .milliseconds(100))

        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        
        await MainActor.run {
            isConnected = false
        }
    }
    
    private func ping() async throws {
        try await webSocket?.sendPing()
    }
    
    private func handleConnectionError(_ error: Error) async {
        await MainActor.run {
            isConnected = false
        }
        
        if shouldMaintainConnection {
            do {
                try await reconnect()
            } catch {
                print("Auto-reconnect failed: \(error)")
            }
        }
    }
    
    private func reconnect() async throws {
        guard shouldMaintainConnection else { return }
        
        await disconnect()
        
        // Exponential backoff for reconnection attempts
        if reconnectionAttempts < maxReconnectionAttempts {
            reconnectionAttempts += 1
            let delay = min(reconnectionDelay * pow(2.0, Double(reconnectionAttempts - 1)), 30.0)
            
            print("Reconnecting in \(delay) seconds (attempt \(reconnectionAttempts)/\(maxReconnectionAttempts))")
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            
            try await connect()
        } else {
            print("Max reconnection attempts reached. Connection will retry when app becomes active.")
            reconnectionAttempts = 0
        }
    }
    
    // MARK: - Messaging methods
    
    func sendMessage(_ text: String, ocrText: String? = nil, selectedText: String? = nil, smarterAnalysisEnabled: Bool = false) async throws {
        await MainActor.run {
            if !messageStream.isEmpty {
                lastMessages.append(MessageData(message: messageStream, isUser: false))
            }
            lastMessages.append(MessageData(message: text, isUser: true))
            messageStream = ""
        }
        
        // Ensure connection is active before sending
        if !isConnected && shouldMaintainConnection {
            try await connect()
        }
        
        guard isConnected else {
            throw NSError(domain: "AIConnectionManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not connected to server"])
        }
        
        // Create and store user message
        let metadata = AIMessageMetadata(
            ocrText: contextManager.ocrText.isEmpty ? nil : contextManager.ocrText,
            selectedText: contextManager.selectedText.isEmpty ? nil : contextManager.selectedText
        )
        let userMessage = AIMessage(role: "user", content: text, metadata: metadata)
        messageHistory.append(userMessage)
        
        // Always send image data
        let base64ImageBytes: String? = contextManager.imageBytes?.base64EncodedString()
        
        // Create request with messages and imageBytes separately
        let request = AIRequest(messages: messageHistory, imageBytes: base64ImageBytes, smarterAnalysisEnabled: smarterAnalysisEnabled)
        
        await MainActor.run {
            isReceiving = true
        }
        let jsonData = try JSONEncoder().encode(request)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw NSError(domain: "AIConnectionManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to encode JSON data as UTF-8 string"])
        }
        try await webSocket?.send(.string(jsonString))
    }
    
    private func handleReceivedData(_ data: Data) {
        do {
            let response = try JSONDecoder().decode(AIResponse.self, from: data)
            
            DispatchQueue.main.async {
                self.messageStream = response.content
                
                if response.isComplete {
                    self.isReceiving = false
                    // Add assistant message to history when complete
                    let assistantMessage = AIMessage(role: "assistant", content: response.content)
                    self.messageHistory.append(assistantMessage)
                }
            }
        } catch {
            print("Error decoding response: \(error)")
        }
    }
    
    private func handleReceivedText(_ text: String) {
        DispatchQueue.main.async {
            // Handle streaming responses character by character or chunk by chunk
            if self.isReceiving{
                self.isReceiving = false
                self.messageStream = text
            }
            else{
                self.messageStream += text
                // Remove any whitespace that slips in directly before punctuation characters like `'`, `"`, ```, or `,` at the end of the string.
                // Regex: one or more whitespace characters followed by any target punctuation at the end → keep only the punctuation.
                self.messageStream = self.messageStream.replacingOccurrences(
                    of: "\\s+([,'`\"])$",
                    with: "$1",
                    options: .regularExpression
                )
            }
        }
    }
    
    // MARK: - Helpers
    
    func clearConversation() {
        messageHistory.removeAll()
        messageStream = ""
    }
    
    /// Get connection status for debugging
    func getConnectionStatus() -> String {
        return """
        Connected: \(isConnected)
        Should Maintain: \(shouldMaintainConnection)
        Reconnection Attempts: \(reconnectionAttempts)
        WebSocket State: \(webSocket?.state.rawValue ?? -1)
        """
    }
    
    deinit {
        #if canImport(UIKit)
        NotificationCenter.default.removeObserver(self)
        endBackgroundTask()
        #endif
        shouldMaintainConnection = false
        Task {
            await disconnect()
        }
    }
}

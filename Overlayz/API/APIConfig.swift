//
//  APIConfig.swift
//  Overlayz
//
//  Created by AI Assistant on 5/15/25.
//

import Foundation

/// Configuration for API endpoints and common settings
struct APIConfig {
    /// Base server URL for all API calls
    static let baseURL =  "https://itzerhypergalaxy.online"
    // static let baseURL = "http://localhost:8000"

    /// WebSocket URL for real-time connections
    static var websocketURL: String {
        // Convert HTTP to WS protocol
        let wsProtocol = baseURL.hasPrefix("https") ? "wss" : "ws"
        let cleanURL = baseURL.replacingOccurrences(of: "https://", with: "")
                              .replacingOccurrences(of: "http://", with: "")
        return "\(wsProtocol)://\(cleanURL)"
    }
    
    /// API timeout intervals
    struct Timeouts {
        static let standard: TimeInterval = 30.0
        static let extended: TimeInterval = 60.0
        static let websocket: TimeInterval = 120.0
    }
    
    /// Common headers for API requests
    static var defaultHeaders: [String: String] {
        return [
            "Content-Type": "application/json",
            "Accept": "application/json"
        ]
    }
} 
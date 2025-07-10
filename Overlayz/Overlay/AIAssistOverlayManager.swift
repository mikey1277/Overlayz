//
//  AIAssistOverlayManager.swift
//  Overlayz
//
//  Created by AI Assistant on 5/15/25.
//

import Cocoa
import SwiftUI
import Carbon
import Combine

/// Manages a floating AI-assist chat overlay that can be d with a global hot-key.
final class AIAssistOverlayManager: ObservableObject {

    // MARK: - Singleton
    static let shared = AIAssistOverlayManager()
    
    // MARK: - Published properties
    @Published var isVisible: Bool = false
    
    // MARK: - Private properties
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Manager references
    private let contextManager = AIContextManager.shared

    lazy var windowViewController = AIAssistWindowController()
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Notification handling
    @objc private func windowDidClose(_ notification: Notification) {
        resetState()
        isVisible = false
    }

    // MARK: - Public helpers
    private func resetState() {
        AIConnectionManager.shared.lastMessages.removeAll()
        AIConnectionManager.shared.messageStream = ""
        // Stop any ongoing receiving state
        Task { @MainActor in
            AIConnectionManager.shared.isReceiving = false
        }
    }
    
    // Add function to print selected text
    private func printSelectedText() {
        let selectedText = contextManager.selectedText
        if !selectedText.isEmpty {
            print("=== AI ASSIST OVERLAY - SELECTED TEXT ===")
            print("Content: \(selectedText)")
            print("Length: \(selectedText.count) characters")
            print("First 100 chars: \(String(selectedText.prefix(100)))")
            print("=======================================")
        } else {
            print("=== AI ASSIST OVERLAY - NO SELECTED TEXT ===")
        }
    }
    
    func stop(){
        windowViewController.window?.orderOut(nil)
        resetState()
        isVisible = false
    }
    
    func toggle() {
        if windowViewController.window?.isVisible ?? false {
            stop()
            return
        }

        // Reset state when opening fresh
        resetState()

        // 1. Determine current mouse position in global screen coordinates
        var mousePoint = NSEvent.mouseLocation

        // 2. Identify the screen containing the mouse (fallback to main)
        let targetScreen = NSScreen.screens.first { NSMouseInRect(mousePoint, $0.frame, false) } ?? NSScreen.main
        guard let window = windowViewController.window else{return}

        if let screen = targetScreen {
            // Clamp mousePoint to that screen coordinates (already in global coords)
            // 3. Center the window on the mouse location
            var extraSpace: CGFloat = 350
            let windowSize = window.frame.size
            let verticalOffset: CGFloat = 50 - extraSpace
            let horizontalOffset: CGFloat = -30
            var originX: CGFloat
            let leftAlignedX = mousePoint.x + horizontalOffset
            if leftAlignedX + windowSize.width <= screen.frame.maxX {
                // Enough space to show the whole window to the right of the cursor – use left alignment.
                originX = leftAlignedX
            } else {
                // Near the right edge; keep the window inside the screen by right-aligning it.
                originX = mousePoint.x - windowSize.width - horizontalOffset
            }
            var originY: CGFloat
            let offsetY: CGFloat = -70

            // Prefer placing the window below the cursor, offsetting its top edge by 300 px.
            let belowOriginY = mousePoint.y - verticalOffset - windowSize.height
            if belowOriginY >= screen.frame.minY {
                originY = belowOriginY + offsetY
            } else {
                // Not enough space below; place the window above the cursor so its bottom edge is 300 px higher.
                originY = mousePoint.y + verticalOffset + -1 * offsetY
            }

            // 4. Ensure the window remains fully visible within the screen bounds
            let minX = screen.frame.minX
            let maxX = screen.frame.maxX - windowSize.width
            let minY = screen.frame.minY
            let maxY = screen.frame.maxY - windowSize.height + extraSpace

            originX = max(minX, min(originX, maxX))
            originY = max(minY, min(originY, maxY))

            window.setFrameOrigin(NSPoint(x: originX, y: originY))
        }

        // Capture current context when showing the window
        Task{
            try await contextManager.captureCurrentContext(captureImage: true)
            // Print selected text after capturing context
            await MainActor.run {
                printSelectedText()
            }
        }
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        isVisible = true
    }
    
    // MARK: - Message handling
    
}


// MARK: - SwiftUI content
// Moved to separate file AIAssistView.swift 

//
//  AIAssistWindowController.swift
//  Overlayz
//
//  Created by occlusion on 6/1/25.
//


import Cocoa
import SwiftUI
import Combine
import Cocoa

/// A borderless window that allows moving its frame completely off-screen,
/// including transparent areas, by handling mouse events manually.
class KeyableBorderlessWindow: NSWindow {
    /// Stores the offset between the window's origin and the initial click point
    private var initialClickOffset: NSPoint = .zero

    override var canBecomeKey: Bool { true }
    override var acceptsFirstResponder: Bool { true }

}

class AIAssistWindowController: NSWindowController {
    
    
    override func windowDidLoad() {
        super.windowDidLoad()
        
        // Print selected text debug info when window loads
        printWindowDebugInfo()
    
        // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
    }
    
    var subscribers = Set<AnyCancellable>()
    
    // Add debug function for selected text
    private func printWindowDebugInfo() {
        let contextManager = AIContextManager.shared
        print("=== AI ASSIST WINDOW CONTROLLER DEBUG ===")
        print("Window loaded at: \(Date())")
        print("Has selected text: \(!contextManager.selectedText.isEmpty)")
        if !contextManager.selectedText.isEmpty {
            print("Selected text preview: \(String(contextManager.selectedText.prefix(50)))...")
        }
        print("========================================")
    }

    convenience init() {
        let autosaveName = "OverlayWindowFrame"
        
        
        // 3) Calculate total window size (icon + padding)
        let totalSize = NSSize(width: 1000, height: 1000)
        
        
        // 4) Initialize NSWindow with contentRect, styleMask, backing and defer
        let window = KeyableBorderlessWindow(
            contentRect: NSRect(origin: .zero, size: totalSize),
            styleMask: [.borderless, .fullSizeContentView],             // make the window borderless
            backing: .buffered,
            defer: false
        )

        // 1) Create the SwiftUI icon view
        let iconView = AIAssistView(window: window)
        
        // 2) Wrap the SwiftUI view in an NSHostingController
        let hostingController = NSHostingController(rootView: iconView)

        // 5) Assign the contentViewController
        window.contentViewController = hostingController
        window.animationBehavior     = .utilityWindow
//        window.animatesWhenResized   = true
        // 6) Make window transparent
        window.isOpaque = false
        window.backgroundColor = NSColor.clear
        
        // 7) Float above all normal windows
        window.level = .statusBar
        
        // 8) Make disappear from screen recordings and other apps

        window.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        
        // 9) Add subtle shadow for depth
        window.hasShadow = false
        
        // 11) Center and show
        window.center()

        // 11) Enable automatic frame saving/restoring
        window.setFrameAutosaveName(autosaveName)
        // Try to restore saved frame; if none exists, fallback to bottom-left
        if !window.setFrameUsingName(autosaveName) {
            if let screenFrame = NSScreen.main?.visibleFrame {
                window.setFrameOrigin(
                    CGPoint(x: screenFrame.minX, y: screenFrame.minY)
                )
            }
        }
        
        // 10) Allow dragging by clicking anywhere in background
        window.isMovableByWindowBackground = true
        
        // 12) Initialize the window controller with our window
        self.init(window: window)
        window.setContentSize(NSSize(width: 500, height: 400))
        
    }
    


}

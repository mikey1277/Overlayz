//
//  SettingsWindowController.swift
//  Overlayz
//
//  Created by occlusion on 6/1/25.
//


import Cocoa
import SwiftUI
import Combine
import Cocoa


class SettingsWindowController: NSWindowController, NSWindowDelegate {
    
    
    override func windowDidLoad() {
        super.windowDidLoad()
    }
    
    convenience init() {
        let autosaveName = "SettingsWindowFrame"
        
        
        // 3) Calculate total window size (icon + padding)
        let totalSize = NSSize(width: 1000, height: 1000)
        
        
        // 4) Initialize NSWindow with contentRect, styleMask, backing and defer
        let window = KeyableBorderlessWindow(
            contentRect: NSRect(origin: .zero, size: totalSize),
            styleMask: [    .titled,
                            .fullSizeContentView,
                            .closable,
                            .miniaturizable,
                            .resizable],             // make the window borderless
            backing: .buffered,
            defer: false
        )
        

        // 1) Create the SwiftUI icon view
        let iconView = SettingsView(window: window)
        
        // 2) Wrap the SwiftUI view in an NSHostingController
        let hostingController = NSHostingController(rootView: iconView)

        window.titlebarAppearsTransparent = true
        // 5) Assign the contentViewController
        window.contentViewController = hostingController
        window.animationBehavior     = .utilityWindow
//        window.animatesWhenResized   = true
        // 6) Make window transparent
        window.isOpaque = false
        window.backgroundColor = NSColor.clear
        
        // 7) Float above all normal windows
        window.level = .statusBar

        
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
        window.setContentSize(NSSize(width: 500, height: 720))
        window.delegate = self

        
    }

    
    func show(){
        NSApp.setActivationPolicy(.regular)
        self.showWindow(self)
        NSApp.activate(ignoringOtherApps: true)
        self.window?.center()
        self.window?.makeKeyAndOrderFront(self)

    }
    
    override func close() {
        super.close()

    }
    
    
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

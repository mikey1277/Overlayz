//
//  InputEventManager.swift
//  Overlayz
//
//  Created by occlusion on 5/4/25.
//

import Cocoa
import Carbon
import SwiftUI

extension Notification.Name {
    static let shortcutTriggered = Notification.Name("ShortcutTriggered")
}

class InputEventModel: ObservableObject{
    @AppStorage("AIAssistShortcut") var aiAssistShortcut: Shortcut = Shortcut(key: "1", modifiers: [.command, .shift])
    @AppStorage("QuickCaptureShortcut") var quickCaptureShortcut: Shortcut = Shortcut(key: "2", modifiers: [.command, .shift])
    @AppStorage("AutoContextShortcut") var autoContextShortcut: Shortcut = Shortcut(key: "O", modifiers: [.command, .shift])
}

class InputEventManager: NSObject {
    
    let model = InputEventModel()
    
    static let shared = InputEventManager()
    
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?
    var requestCallback:((Shortcut)->Bool)? = nil
    
    deinit{
        cleanup()
    }
    
    func setup(){
        
        // Create a new event tap
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        
        // Callback function for the event tap
        let callback: CGEventTapCallBack = { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
            
            guard let refcon = refcon else{ return Unmanaged.passRetained(event)}
            let original = Unmanaged<InputEventManager>
                .fromOpaque(refcon)
                .takeUnretainedValue()
            
            if type == .keyDown {
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags

                if let cb = original.requestCallback{
                    if cb(Shortcut(key: CGKeyCode(keyCode).toString() ?? "", modifiers: flags.modifierFlags)){
                        original.requestCallback = nil
                        return nil
                    }
                }

                // Check AI Assist shortcut
                let aiAssistShortcut = original.model.aiAssistShortcut
                var code = aiAssistShortcut.key.firstCGKeyCode ?? 0
                if aiAssistShortcut.modifiers == flags.modifierFlags && keyCode == code {
                    AIAssistOverlayManager.shared.toggle()
                    NotificationCenter.default.post(name: .shortcutTriggered, object: nil, userInfo: ["type": "aiAssist"])
                    return nil
                }

                // Check AutoContext shortcut (cmd+shift+3)
                let autoContextShortcut = original.model.autoContextShortcut
                code = autoContextShortcut.key.firstCGKeyCode ?? 0
                if autoContextShortcut.modifiers == flags.modifierFlags && keyCode == code {
                    AutoContextOverlay.instance.toggle()
                    NotificationCenter.default.post(name: .shortcutTriggered, object: nil, userInfo: ["type": "autoContext"])
                    return nil
                }

                // Check QuickCapture shortcut (cmd+shift+2) 
                let quickCaptureShortcut = original.model.quickCaptureShortcut
                code = quickCaptureShortcut.key.firstCGKeyCode ?? 0
                if quickCaptureShortcut.modifiers == flags.modifierFlags && keyCode == code {
                    QuickCaptureOverlay.instance.toggle()
                    NotificationCenter.default.post(name: .shortcutTriggered, object: nil, userInfo: ["type": "quickCapture"])
                    return nil
                }
/*
                // Hard-coded shortcut: Cmd + Shift + 1 to toggle AI Assist overlay (fallback)
                if flags.contains(.maskCommand) && flags.contains(.maskShift) && keyCode == 18 {
                    AIAssistOverlayManager.shared.toggle()
                    return nil
                }
                
                // Hard-coded shortcut: Cmd + Shift + 2 to toggle QuickCapture overlay (fallback)
                if flags.contains(.maskCommand) && flags.contains(.maskShift) && keyCode == 19 {
                    QuickCaptureOverlay.instance.toggle()
                    return nil
                }
                
                // Hard-coded shortcut: Cmd + Shift + 3 to toggle AutoContext overlay (fallback)
                if flags.contains(.maskCommand) && flags.contains(.maskShift) && keyCode == 20 {
                    AutoContextOverlay.instance.toggle()
                    return nil
                }
 */
            }
            
            return Unmanaged.passRetained(event)
        }
        
        // Create the event tap
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: userInfo
        ) else {
            print("Failed to create event tap")
            return
        }
        
        // Create a run loop source and add it to the run loop
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        
        // Enable the event tap
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        // Store references
        self.eventTap = eventTap
        self.runLoopSource = runLoopSource

    }
    
    func cleanup(){
        if let eventTap = eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
        
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }

    }
}

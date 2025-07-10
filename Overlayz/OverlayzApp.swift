//
//  OverlayzApp.swift
//  Overlayz
//
//  Created by Teju Sharma on 4/26/25.
//

import SwiftUI
import AppKit
import Carbon
import Vision
import ScreenCaptureKit
import Sparkle
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, ObservableObject {
    
    static var shared: AppDelegate!
    lazy var settingsWindow = SettingsWindowController()
    var setupWindow = SetupWindowController()
    let updaterController: SPUStandardUpdaterController
 
    override init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        super.init()
        AppDelegate.shared = self
    }

    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Temporarily reset UserDefaults
        // let domain = Bundle.main.bundleIdentifier!
        // UserDefaults.standard.removePersistentDomain(forName: domain)
        // UserDefaults.standard.synchronize()
        
        let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

        if !isPreview {
            // Debug font availability
            Font.debugFontAvailability()
            
            // Initialize AuthManager
            _ = AuthManager.shared
            
            setupWindow.showIfNeeded {
                InputEventManager.shared.setup()
            }
            
            SystemMenuManager.shared.showSettings = { [weak self] in
                self?.settingsWindow.show()
            }
            
            SystemMenuManager.shared.setup()
        }

    }
    

    func applicationWillTerminate(_ notification: Notification) {
        // Clean up resources when app terminates
    }
    
}


@main
struct OverlayzApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings { }
    }
}

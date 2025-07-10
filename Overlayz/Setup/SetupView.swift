//
//  SetupView.swift
//  Overlayz
//
//  Created by occlusion on 5/4/25.
//

import SwiftUI
import AppKit // Needed for NSEvent keyboard monitoring

struct SetupView: View {
    @AppStorage("FinishFirstTime") var finishFirstTime: Bool = false
    @AppStorage("FinishSetup") var finishSetup: Bool = false
    @AppStorage("Shortcut") private var shortcut: Shortcut = Shortcut(key: "", modifiers: [])
    @AppStorage("HasSeenWelcome") private var hasSeenWelcome: Bool = false

    @State private var showFloatingOnboarding: Bool = false
    @State private var animateToSmallWindow: Bool = false
    @State private var eventMonitor: Any? // Global keyboard listener during setup
    
    // MARK: - TEMPORARY: Skip to floating controller
    @State private var skiptofloating: Bool = false
    
    var didFinish: (() -> Void)? = nil

    @ObservedObject var model = PermissionManager.shared.model
    
    // MARK: - TEMPORARY: Force reset for testing
    init(didFinish: (() -> Void)? = nil) {
        self.didFinish = didFinish
        // Temporarily reset to show welcome screen
        UserDefaults.standard.set(false, forKey: "FinishFirstTime")
        
        // TEMPORARY: Also reset floating onboarding flag for testing
        // UserDefaults.standard.set(false, forKey: "HasSeenFloatingOnboarding")
        // Uncomment the line above if you want to test floating onboarding again
    }

    var body: some View {
        VStack {
            // Check if we should skip to floating onboarding
            if skiptofloating {
                VStack {
                    Text("Skipping to Floating Onboarding...")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding()
                }
                .onAppear {
                    // Small delay to show the message briefly, then proceed
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        didFinish?()
                    }
                }
            } else {
                 if !finishFirstTime && !hasSeenWelcome {
                     WelcomeView {
                         finishFirstTime = true
                         hasSeenWelcome = true
                     }
                 }
                 else {
                     // Skip welcome if already seen, but make sure finishFirstTime is set
                     if !finishFirstTime && hasSeenWelcome {
                         // Auto-advance past welcome for returning users
                         Text("")
                             .onAppear {
                                 finishFirstTime = true
                             }
                     }
                     else if !model.accessibilityPermission{
                        PermissionTemplateView(
                            title: "To assist you anytime, \nOverlayz needs \naccessibility access.",
                             subtitle: "",
                             isPermissionGranted: model.accessibilityPermission,
                             onGrantAccess: {
                                 PermissionManager.shared.requestAccessibilityPermission()
                             },
                             onNeedHelp: {
                                 // Handle need help for accessibility
                                 // You can add help URL or instruction modal here
                             },
                             onNextStep: {
                                 // This will be automatically handled by the permission state change
                             },
                             image: "ai-assist-ss"
                         )
                     }
                     else if !model.screenCapturePermission{
                         if model.screenCaptureRequireRestart{
                             // Special case for restart requirement
                             VStack {
                                 Text("Screen Recording Permission Required")
                                     .font(.system(size: 20, weight: .semibold)).padding()
                            
                                 Spacer()

                                 Text("Required to Restart app to enable Screen Capture Permission.")
                                     .multilineTextAlignment(.center)
                                     .padding()

                                 Spacer()
                                 Button("Restart App"){
                                     PermissionManager.shared.restartApp()
                                 }.padding()
                             }
                         } else {
                            PermissionTemplateView(
                                title: "Now to automatically analyze your screen (even images!), \nOverlayz needs \nscreen access.",
                                 subtitle: "",
                                 isPermissionGranted: model.screenCapturePermission,
                                 onGrantAccess: {
                                     PermissionManager.shared.requestScreenCapturePermission()
                                 },
                                 onNeedHelp: {
                                     // Handle need help for screen capture
                                     // You can add help URL or instruction modal here
                                 },
                                 onNextStep: {
                                     // This will be automatically handled by the permission state change
                                 },
                                 image: "slack-ss"
                             )
                         }
                     }
                     else {
                        VStack {
                            Text("All Set!")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.primary)
                                .padding()

                            Button("Continue"){
                                didFinish?()
                            }.padding()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .colorScheme(.light)
        .cornerRadius(20)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .inset(by: 0.5)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
        .onAppear {
            startGlobalShortcutMonitoring()
        }
        .onDisappear {
            stopGlobalShortcutMonitoring()
        }
    }

    // MARK: - Global Shortcut Monitoring
    private func startGlobalShortcutMonitoring() {
        // If the global event tap is already active, avoid adding a duplicate local monitor.
        guard InputEventManager.shared.eventTap == nil else { return }

        // Ensure we don't add multiple monitors
        stopGlobalShortcutMonitoring()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handleKeyEvent(event)
        }
    }

    private func stopGlobalShortcutMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        let pressedModifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let pressedKey = event.keyCode.keyCodeToString

        // Shortcut references
        let aiAssistShortcut = InputEventManager.shared.model.aiAssistShortcut
        let quickCaptureShortcut = InputEventManager.shared.model.quickCaptureShortcut
        let autoContextShortcut = InputEventManager.shared.model.autoContextShortcut

        // Helper closure to match shortcuts
        func shortcutMatches(target: Shortcut) -> Bool {
            var targetModifiers: NSEvent.ModifierFlags = []
            if target.modifiers.contains(.command) { targetModifiers.insert(.command) }
            if target.modifiers.contains(.shift) { targetModifiers.insert(.shift) }
            if target.modifiers.contains(.option) { targetModifiers.insert(.option) }
            if target.modifiers.contains(.control) { targetModifiers.insert(.control) }
            return pressedKey.lowercased() == target.key.lowercased() && pressedModifiers == targetModifiers
        }

        if shortcutMatches(target: aiAssistShortcut) {
            QuickCaptureOverlay.instance.stop()
            AutoContextOverlay.instance.stop()
            AIAssistOverlayManager.shared.toggle()
            return nil
        }

        if shortcutMatches(target: quickCaptureShortcut) {
            AIAssistOverlayManager.shared.stop()
            AutoContextOverlay.instance.stop()
            QuickCaptureOverlay.instance.toggle()
            return nil
        }

        if shortcutMatches(target: autoContextShortcut) {
            QuickCaptureOverlay.instance.stop()
            AIAssistOverlayManager.shared.stop()
            AutoContextOverlay.instance.toggle()
            return nil
        }

        return event
    }
}

#Preview {
    SetupView()
}

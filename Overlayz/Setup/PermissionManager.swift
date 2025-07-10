//
//  PermissionManager.swift
//  Overlayz
//
//  Created by occlusion on 5/4/25.
//

import Cocoa


class PermissionModel: ObservableObject {

    var isRequiredToShowPermission:Bool{
        return isRequiredToGrant
    }

    var isRequiredToGrant:Bool{
        let result = !screenCapturePermission || !accessibilityPermission
        return result
    }
    @Published var screenCapturePermission = false
    @Published var screenCaptureRequireRestart = false
    @Published var accessibilityPermission = false
}

class PermissionManager: NSObject{
    
    @objc static let shared = PermissionManager()
    
    let model = PermissionModel()
    
    @objc var isRequiredToShow:Bool{
        let result = !screenCapturePermission || !accessibilityPermission
        return result
    }
    
    @objc var screenCapturePermission:Bool{
        return CGPreflightScreenCaptureAccess()
    }
    
    @objc var accessibilityPermission:Bool{
        return AXIsProcessTrusted()
    }
    
    var checkTimer: Timer?
    var lastStatus = false
    var didFinish:(()->Void)? = nil

    
    override init() {
        
        super.init()
        
        self.lastStatus = self.isRequiredToShow

        checkTimer?.invalidate()
        checkTimer = Timer(timeInterval: 1.0, repeats: true, block: { timer in
            self.checkPermission()
        })
        
        self.checkPermission()

        RunLoop.main.add(checkTimer!, forMode: .common)


    }
    
    func checkPermission() {
        self.model.screenCapturePermission = self.screenCapturePermission
        self.model.accessibilityPermission = self.accessibilityPermission
        
        if let cliURL = Bundle.main.url(forResource: "ScreenCapturePermissionHelper", withExtension: nil, subdirectory: ""){
            let proc = Process()
            proc.executableURL = cliURL
            let pipe = Pipe()
            proc.standardOutput = pipe
            try? proc.run()
            proc.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let str = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let permission = str == "1"
            if permission, self.model.screenCapturePermission == false{
                self.model.screenCaptureRequireRestart = true
            }
            else{
                self.model.screenCaptureRequireRestart = false
            }
        }
        
        if self.lastStatus != self.isRequiredToShow{
            self.lastStatus = self.isRequiredToShow
            if !self.isRequiredToShow{
                self.didFinish?()
                self.didFinish = nil
                checkTimer?.invalidate()
                checkTimer = nil
            }
        }

        // If accessibility permission is newly granted and the global shortcut listener hasn't been started yet,
        // start it now so shortcuts work immediately—even during onboarding.
        if self.model.accessibilityPermission && InputEventManager.shared.eventTap == nil {
            InputEventManager.shared.setup()
        }
    }
    
        
    func requestScreenCapturePermission() {
        guard !screenCapturePermission else{return}
        if !CGRequestScreenCaptureAccess(){
            DispatchQueue.main.asyncAfter(deadline: .now()+1.0, execute: {
                let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
                if let aString = URL(string: urlString) {
                    NSWorkspace.shared.open(aString)
                }
            })
        }
        
    }
    
    func requestAccessibilityPermission() {
        guard !accessibilityPermission else{return}
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
        if !AXIsProcessTrustedWithOptions(options){
            DispatchQueue.main.asyncAfter(deadline: .now()+1.0, execute: {
                let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                if let aString = URL(string: urlString) {
                    NSWorkspace.shared.open(aString)
                }
            })
        }
    }
    
    func restartApp() {
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "sleep \(3.0); open \"\(Bundle.main.bundlePath)\""]
        task.launch()
        
        NSApp.terminate(self)
    }
    
    
}

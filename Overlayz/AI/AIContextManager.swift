//
//  AIContextManager.swift
//  Overlayz
//
//  Created by AI Assistant on 5/15/25.
//

import Foundation
import Combine
import AppKit
import CoreGraphics
import Vision


/// Manages the capture of contextual information from the screen and system
class AIContextManager: ObservableObject {
    // Singleton
    static let shared = AIContextManager()
    
    // Published properties
    @Published var didChangeSelectedText = false
    @Published var selectedText = ""
    @Published var ocrText = ""
    @Published var imageBytes: Data?
    /// The URL of the active tab in the user’s browser (Chrome or Safari). Empty string if unavailable.
    @Published var browserURL: String = ""

    private init() {}
    
    func captureCurrentContext(captureImage: Bool = true) async throws {
        let selected = try await captureSelectedText()
        Task{ @MainActor in
            self.selectedText = selected
        }

        // Capture the current browser URL (supports Google Chrome and Safari)
        print("Getting browser URL")
        let activeURL: String = {
            if let url = getBrowserURL("Google Chrome") {
                print("Google Chrome URL: ", url)
                return url
            }
            if let url = getBrowserURL("Safari") {
                print("Safari URL: ", url)
                return url
            }
            return ""
        }()

        print("activeURL: ", activeURL)

        Task { @MainActor in
            self.browserURL = activeURL
        }
        
        
        // Capture screenshot once and use it for both OCR and storage
        if let image = await WindowCaptureManager.shared.captureMainDisplay() {
            print("Successfully captured image: \(image.width)x\(image.height)")
            
            // Only store image if captureImage is true
            if captureImage {
                let imageData = await MainActor.run {
                    convertCGImageToJPEGData(image)
                }
                
                await MainActor.run {
                    self.imageBytes = imageData
                    
                    if let data = imageData {
                        print("Successfully converted image to JPEG data: \(data.count) bytes")
                    } else {
                        print("Failed to convert image to JPEG data")
                    }
                }
            } else {
                print("Skipping image storage (captureImage = false)")
            }
            
            // Perform OCR on the same image
            let ocrResults = await WindowCaptureManager.shared.performOCR(on: image)
            let combinedText = ocrResults
                .sorted { $0.boundingBoxRaw.origin.y < $1.boundingBoxRaw.origin.y }
                .map { $0.text }
                .joined(separator: " ")
            print("combined text: ", combinedText)
            
            Task{ @MainActor in
                self.ocrText = combinedText
            }
        } else {
            print("Failed to capture image from WindowCaptureManager")
            Task{ @MainActor in
                self.ocrText = ""
                self.imageBytes = nil
            }
        }
  
    }
    
    /// Convert CGImage to JPEG Data for storage and transmission
    private func convertCGImageToJPEGData(_ cgImage: CGImage) -> Data? {
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmapImageRep = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmapImageRep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }
    
    /// Capture text currently selected by the user using accessibility APIs
    func captureSelectedText() async throws -> String{
        DispatchQueue.main.async {
            self.didChangeSelectedText = false
        }
        // First try using the accessibility API
        if let selectedText = await getAllSelectedTextFromOtherApps(), !selectedText.isEmpty {
            Task{@MainActor in
                self.didChangeSelectedText = true
                self.selectedText = selectedText
            }
            return selectedText
        }
        
        // Clear if no text found
        Task{@MainActor in
            self.didChangeSelectedText = true
            self.selectedText = ""
        }
        return ""
    }

    
    
    /// Returns the selected text in other running apps (excluding self),
    /// even if they are not frontmost.
    func getAllSelectedTextFromOtherApps() async -> String? {
        if let window = NSWorkspace.shared.windowBehind(){
/*
            if let text = findSelectedText(in: window.0), !text.isEmpty {
                return text
            }
  */
            return await NSPasteboard.getSelectedText(wid: window.1)
        }
        
        return nil
    }
    
    
    /// Recursively search for an AXUIElement that has kAXSelectedTextAttribute.
    /// - Parameter element: Starting element (e.g. a window)
    /// - Returns: Found selected text or nil
    func findSelectedText(in element: AXUIElement) -> String? {

        var selected: AnyObject?
        let selErr = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selected
        )
        if selErr == .success, let txt = selected as? String, !txt.isEmpty {
            return txt
        }
        
        var children: CFTypeRef?
        let chErr = AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &children
        )
        if chErr == .success, let elems = children as? [AXUIElement] {
            for child in elems {
                if let found = findSelectedText(in: child) {
                    return found
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Browser URL Helpers

    /// Returns the cleaned URL (without scheme or “www.”) of the active tab for the specified browser, if available.
    private func getBrowserURL(_ appName: String) -> String? {
        guard let scriptText = getScriptText(appName) else { return nil }

        var error: NSDictionary?
        guard let script = NSAppleScript(source: scriptText) else { return nil }

        guard let outputString = script.executeAndReturnError(&error).stringValue else {
            if let error = error {
                print("Get Browser URL request failed with error: \(error.description)")
            }
            return nil
        }

        // Clean URL output – remove protocol & unnecessary "www."
        if let url = URL(string: outputString), var host = url.host {
            if host.hasPrefix("www.") {
                host = String(host.dropFirst(4))
            }
            let resultURL = "\(host)\(url.path)"
            return resultURL
        }

        return nil
    }

    /// AppleScript source for fetching the front-most tab/document URL for supported browsers.
    private func getScriptText(_ appName: String) -> String? {
        switch appName {
        case "Google Chrome":
            return "tell app \"Google Chrome\" to get the url of the active tab of window 1"
        case "Safari":
            return "tell application \"Safari\" to return URL of front document"
        default:
            return nil
        }
    }
    
}


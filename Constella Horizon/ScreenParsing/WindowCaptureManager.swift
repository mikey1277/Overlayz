import SwiftUI
import CoreGraphics
import CoreImage
import Vision
import Dispatch
import ScreenCaptureKit
import Combine
import CoreMedia
private let kAXWindowNumberAttribute: CFString = "AXWindowNumber" as CFString


extension CGFloat {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let doubleValue = try container.decode(Double.self)
        self.init(doubleValue)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Double(self))
    }
}

struct TextBoundingBox: Codable {
    var top: CGFloat
    var left: CGFloat
    var width: CGFloat
    var height: CGFloat
}

struct OCRResult: Codable {
    var text: String
    var confidence: Float
    var boundingBoxRaw: CGRect
    var id: Int?
    var boundingBox: TextBoundingBox?

    private enum CodingKeys: String, CodingKey {
        case id
        case text
        case confidence
        case boundingBox = "bbox"
        case boundingBoxRaw
    }
}

//// Managing capture
class WindowCaptureManager {
    static let shared = WindowCaptureManager()
    private var stream: SCStream?
    private var streamOutput: StreamOutput?
    private var contentFilter: SCContentFilter?
    private var lastCaptureImage: CGImage?
    private init() {}

    //// Window based capture
    public func captureWindow(_ windowID: CGWindowID) async -> CGImage? {
        do {
            let windowContent = try await SCShareableContent
                .excludingDesktopWindows(false, onScreenWindowsOnly: true)
            
            guard let window = windowContent.windows.first(
                where: { $0.windowID == windowID }
            ) else {
                return nil
            }
            
            return await captureWithFilter(
                SCContentFilter(desktopIndependentWindow: window)
            )
            
        } catch {
            print("This window specific content not getting: \(error)")
            return nil
        }
    }

    /// This captures the main display
    public func captureMainDisplay() async -> CGImage? {
        
        do {
            let mainDisplay = try await SCShareableContent
                .excludingDesktopWindows(false, onScreenWindowsOnly: true)
            
            guard let display = mainDisplay.displays.first else {
                print("No displays available")
                return nil
            }
            let filter = SCContentFilter(
                display: display,
                excludingApplications: [],
                exceptingWindows: []
            )
            
            return await captureWithFilter(filter)
        } catch {
            print("Error getting shareable content: \(error)")
            return nil
        }
    }

    /// For the image data gotten from above --> do OCR
    public func performOCR(on image: CGImage) async -> [OCRResult] {
        await withCheckedContinuation { continuation in
            let imageSize = CGSize(width: image.width, height: image.height)
            let handler = VNImageRequestHandler(cgImage: image)
                                       
            let request = VNRecognizeTextRequest { request, error in
                let ocrResults: [OCRResult]
                                                  
                if let observations = request.results as? [VNRecognizedTextObservation] {
                    var counter = 0
                    
                    ocrResults = observations.compactMap { obs in
                        guard let candidate = obs.topCandidates(1).first else { return nil }
                        let rect = VNImageRectForNormalizedRect(
                            obs.boundingBox,
                            Int(imageSize.width),
                            Int(imageSize.height)
                        )
                        let bbox = TextBoundingBox(
                            top: rect.origin.y,
                            left: rect.origin.x,
                            width: rect.size.width,
                            height: rect.size.height
                        )
                        defer { counter += 1 }
                        return OCRResult(
                            text: candidate.string,
                            confidence: candidate.confidence,
                            boundingBoxRaw: rect,
                            id: counter,
                            boundingBox: bbox
                        )
                    }
                } else {
                    ocrResults = []
                }
                continuation.resume(returning: ocrResults)
            }
            request.recognitionLanguages = ["en-US"]
            request.recognitionLevel = .accurate
            request.revision = VNRecognizeTextRequestRevision3
                                       
            do {
                try handler.perform([request])
            } catch {
                print("Not able to do OCR: \(error)")
                continuation.resume(returning: [])
            }
        }
    }

    /// Capture and OCR the foreground window or main display.
    public func captureAndProcessText() async -> [OCRResult] {
        /* Used to use the captureForegroundWindow, but that's limited / if there is overlays */
        if let image = await captureMainDisplay() {
            let image2 = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            return await performOCR(on: image)
        }
        return []
    }

    private func captureWithFilter(_ contentFilter: SCContentFilter) async -> CGImage? {
        // Clean up any existing capture stream
        do {
            try await stopCapture()
            
            // Configure stream settings
            let streamConfiguration = SCStreamConfiguration()
            streamConfiguration.capturesAudio = false
            streamConfiguration.showsCursor = false
            
            // Calculate optimal capture dimensions based on content
            let filterContentRect = contentFilter.contentRect
            let pixelScale = contentFilter.pointPixelScale
            
            if filterContentRect.width > 0 && filterContentRect.height > 0 {
                streamConfiguration.width = Int(filterContentRect.width * CGFloat(pixelScale))
                streamConfiguration.height = Int(filterContentRect.height * CGFloat(pixelScale))
            } else {
                // Fallback to default resolution
                streamConfiguration.width = 1920
                streamConfiguration.height = 1080
            }
            
            streamConfiguration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            streamConfiguration.queueDepth = 3
            
            // Initialize stream output handler
            let captureStreamOutput = StreamOutput()
            self.streamOutput = captureStreamOutput
            
            // Capture the frame with timeout handling
            let capturedFrame = await withCheckedContinuation { (frameContinuation: CheckedContinuation<CGImage?, Never>) in
                var hasResumedContinuation = false
                var frameImage: CGImage? = nil
                
                // Set up timeout to prevent indefinite waiting
                let timeoutTask = DispatchWorkItem {
                    guard !hasResumedContinuation else { return }
                    hasResumedContinuation = true
                    frameContinuation.resume(returning: frameImage)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timeoutTask)
                
                // Configure frame capture callback
                captureStreamOutput.captureHandler = { capturedImage in
                    guard !hasResumedContinuation else { return }
                    hasResumedContinuation = true
                    frameImage = capturedImage
                    timeoutTask.cancel()
                    frameContinuation.resume(returning: capturedImage)
                }
                
                // Initialize and start the capture stream
                do {
                    let captureStream = SCStream(filter: contentFilter,
                                               configuration: streamConfiguration,
                                               delegate: nil)
                    
                    try captureStream.addStreamOutput(captureStreamOutput,
                                                    type: .screen,
                                                    sampleHandlerQueue: .main)
                    
                    captureStream.startCapture { startError in
                        if let startError = startError {
                            if !hasResumedContinuation {
                                hasResumedContinuation = true
                                timeoutTask.cancel()
                                frameContinuation.resume(returning: nil)
                            }
                            print("Failed to start capture: \(startError)")
                        } else {
                            self.stream = captureStream
                        }
                    }
                } catch {
                    if !hasResumedContinuation {
                        hasResumedContinuation = true
                        timeoutTask.cancel()
                        frameContinuation.resume(returning: nil)
                    }
                }
            }

            // Brief delay to ensure capture completion
            try await Task.sleep(for: .milliseconds(100))
            try await stopCapture()
            return capturedFrame
            
        } catch {
            return nil
        }
    }

    /// Cleanup function for streams
    private func stopCapture() async throws{
        try await stream?.stopCapture()
        stream = nil
        streamOutput = nil
        contentFilter = nil
    }
}

/// The class to represent stream outputs of the image data
private class StreamOutput: NSObject, SCStreamOutput {
    var captureHandler: ((CGImage?) -> Void)?
    
    func stream(
        _ captureStream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        // Only process screen output type
        guard outputType == .screen,
              let frameHandler = captureHandler,
              sampleBuffer.isValid else { 
            return 
        }
        
        // Extract frame attachments and validate status
        guard let sampleAttachmentsArray = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer,
                createIfNecessary: false
              ) as? [[SCStreamFrameInfo: Any]],
              let frameAttachments = sampleAttachmentsArray.first,
              let frameStatusRaw = frameAttachments[SCStreamFrameInfo.status] as? Int,
              let frameStatus = SCFrameStatus(rawValue: frameStatusRaw),
              frameStatus == .complete else { 
            return 
        }
        
        // Extract pixel buffer and convert to CGImage
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { 
            return 
        }
        
        let coreImage = CIImage(cvPixelBuffer: pixelBuffer)
        let imageContext = CIContext()
        
        if let finalCGImage = imageContext.createCGImage(coreImage, from: coreImage.extent) {
            frameHandler(finalCGImage)
        }
    }
}

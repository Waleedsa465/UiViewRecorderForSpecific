//
//  ImageToVideo.swift
//  recordUIVIew
//
//  Created by Dixit Akabari on 3/25/21.
//  Copyright © 2020 Dixit Akabari. All rights reserved.
//


import AVFoundation
import UIKit
import Photos
import AVKit

var tempurl = ""

struct RenderSettings {
    var width: CGFloat
    var height: CGFloat
    var fps: Int32 = 60
    var avCodecKey = AVVideoCodecType.h264
    var videoFilename = "ImageToVideo"
    var videoFilenameExt = "mp4"
    
    var size: CGSize {
        return CGSize(width: width, height: height)
    }
    
    var outputURL: URL {
        
        let fileManager = FileManager.default
        if let tmpDirURL = try? fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
            return tmpDirURL.appendingPathComponent(videoFilename).appendingPathExtension(videoFilenameExt) as URL
        }
//        fatalError("URLForDirectory() failed")
        return URL(fileURLWithPath: "Failed To generate Link.")
    }
}

class VideoWriter {
    
    let renderSettings: RenderSettings
    
    var videoWriter: AVAssetWriter!
    var videoWriterInput: AVAssetWriterInput!
    var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor!
    
    var isReadyForData: Bool {
        return videoWriterInput?.isReadyForMoreMediaData ?? false
    }
    
    class func pixelBufferFromImage(image: UIImage, pixelBufferPool: CVPixelBufferPool, size: CGSize) -> CVPixelBuffer {
        
        autoreleasepool {
            
            var pixelBufferOut: CVPixelBuffer? = nil
            let options: [CFString: Any] = [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true
            ]
            let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_32ARGB, options as CFDictionary, &pixelBufferOut)
            
            if status != kCVReturnSuccess {
                fatalError("CVPixelBufferPoolCreatePixelBuffer() failed")
            }
            
            let pixelBuffer = pixelBufferOut!
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            let data = CVPixelBufferGetBaseAddress(pixelBuffer)
            let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
            let context = CGContext(data: data, width: Int(size.width), height: Int(size.height),
                                    bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                    space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
            
            context!.setFillColor(UIColor.clear.cgColor)
            context!.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
            context!.interpolationQuality = .high
            
            let aspectWidth = size.width / image.size.width
            let aspectHeight = size.height / image.size.height
            let aspectRatio = min(aspectWidth, aspectHeight)
            let scaledWidth = image.size.width * aspectRatio
            let scaledHeight = image.size.height * aspectRatio
            
            let x = (size.width - scaledWidth) / 2
            let y = (size.height - scaledHeight) / 2
            
            context!.draw(image.cgImage!, in: CGRect(x: x, y: y, width: scaledWidth, height: scaledHeight))
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            
            return pixelBuffer
        }
    }
    
    init(renderSettings: RenderSettings) {
        self.renderSettings = renderSettings
    }
    
    func start() {
        
        let avOutputSettings: [String: AnyObject] = [
            AVVideoCodecKey: renderSettings.avCodecKey as AnyObject,
            AVVideoWidthKey: renderSettings.width as AnyObject,
            AVVideoHeightKey: renderSettings.height as AnyObject,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: NSNumber(value: 12_000_000),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ] as AnyObject
        ]
        
        func createPixelBufferAdaptor() {
            let sourcePixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32ARGB),
                kCVPixelBufferWidthKey as String: NSNumber(value: Float(renderSettings.width)),
                kCVPixelBufferHeightKey as String: NSNumber(value: Float(renderSettings.height))
            ]
            pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoWriterInput,
                                                                      sourcePixelBufferAttributes: sourcePixelBufferAttributes)
        }
        
        func createAssetWriter(outputURL: URL) -> AVAssetWriter {
            guard let assetWriter = try? AVAssetWriter(outputURL: outputURL, fileType: AVFileType.mp4) else {
                fatalError("AVAssetWriter() failed")
            }
            
            guard assetWriter.canApply(outputSettings: avOutputSettings, forMediaType: AVMediaType.video) else {
                fatalError("canApplyOutputSettings() failed")
            }
            
            return assetWriter
        }
        
        videoWriter = createAssetWriter(outputURL: renderSettings.outputURL)
        videoWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: avOutputSettings)
        
        if videoWriter.canAdd(videoWriterInput) {
            videoWriter.add(videoWriterInput)
        }
        else {
            fatalError("canAddInput() returned false")
        }
        
        
        createPixelBufferAdaptor()
        
        if videoWriter.startWriting() == false {
            fatalError("startWriting() failed")
        }
        
        videoWriter.startSession(atSourceTime: CMTime.zero)
        
        precondition(pixelBufferAdaptor.pixelBufferPool != nil, "nil pixelBufferPool")
    }
    
    
    func render(appendPixelBuffers: @escaping (VideoWriter)->Bool, completion: @escaping ()->Void) {

        autoreleasepool {
            
            precondition(videoWriter != nil, "Call start() to initialze the writer")

            let queue = DispatchQueue(label: "mediaInputQueue")
            videoWriterInput.requestMediaDataWhenReady(on: queue) {
                let isFinished = appendPixelBuffers(self)
                if isFinished {
                    self.videoWriterInput.markAsFinished()
                    self.videoWriter.finishWriting {
                        DispatchQueue.main.async {
                            completion()
                            self.videoWriter.cancelWriting()
                        }
                    }
                }
            }
        }
        
    }
    
    func addImage(image: UIImage, withPresentationTime presentationTime: CMTime) -> Bool {
        
        autoreleasepool {
            precondition(pixelBufferAdaptor != nil, "Call start() to initialze the writer")
            
            let pixelBuffer = VideoWriter.pixelBufferFromImage(image: image, pixelBufferPool: pixelBufferAdaptor.pixelBufferPool!, size: renderSettings.size)
            return pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime)
        }
            
    }
    
}

class ImageAnimator {
    
    static let kTimescale: Int32 = 1000
    
    var settings: RenderSettings
    let videoWriter: VideoWriter
    var images: [URL]!
    
    var frameNum = 0
    
    class func removeFileAtURL(fileURL: URL) {
        do {
            try FileManager.default.removeItem(atPath: fileURL.path)
        } catch {
            print("Could not remove file: \(error)")
        }
    }
    
    init(renderSettings: RenderSettings,imagearr: [URL]) {
        settings = renderSettings
        
        // Check if the first image exists and get its size
        if let firstImagePath = imagearr.first?.path,
           let firstImage = UIImage(contentsOfFile: firstImagePath) {
            // Update render settings based on the first image's size
            settings.width = firstImage.size.width
            settings.height = firstImage.size.height
        }
        
        videoWriter = VideoWriter(renderSettings: settings)
        images = imagearr
    }
    
    func render(completion: @escaping ()->Void) {
        
        // The VideoWriter will fail if a file exists at the URL, so clear it out first.
        ImageAnimator.removeFileAtURL(fileURL: settings.outputURL)
        
        videoWriter.start()
        videoWriter.render(appendPixelBuffers: appendPixelBuffers) {
            let s: String = self.settings.outputURL.path
            tempurl = s
            completion()
        }
        
    }
    
    func appendPixelBuffers(writer: VideoWriter) -> Bool {
        
        let frameDuration = CMTimeMake(value: Int64(ImageAnimator.kTimescale / settings.fps), timescale: ImageAnimator.kTimescale)
        
        while !images.isEmpty {
            
            if writer.isReadyForData == false {
                return false
            }
            
            let image = images.removeFirst()
            
            if let dicImage = UIImage(contentsOfFile: image.path) {
                
                // Adjust the render settings for each image if necessary
                if dicImage.size.width != settings.width || dicImage.size.height != settings.height {
                    settings.width = dicImage.size.width
                    settings.height = dicImage.size.height
                }
                
                let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameNum))
                let success = videoWriter.addImage(image: dicImage, withPresentationTime: presentationTime)
                if success == false {
                    fatalError("addImage() failed")
                }
                
                frameNum=frameNum+1
            }
            
        }
        
        return true
    }
    
}


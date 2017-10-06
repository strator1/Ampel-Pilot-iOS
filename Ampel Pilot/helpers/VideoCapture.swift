//
//  VideoCapture.swift
//  Ampel Pilot
//
//  Created by Patrick Valenta on 03.10.17.
//  Copyright © 2017 Patrick Valenta. All rights reserved.
//

import UIKit
import AVFoundation
import CoreVideo

public protocol VideoCaptureDelegate: class {
    func videoCapture(_ capture: VideoCapture, didCaptureVideoFrame: CVPixelBuffer?, timestamp: CMTime)
    
    func videoCaptureDidStop(_ capture: VideoCapture)
    func videoCaptureDidStart(_ capture: VideoCapture)
}

public class VideoCapture: NSObject {
    public var previewLayer: AVCaptureVideoPreviewLayer?
    public weak var delegate: VideoCaptureDelegate?
    public var fps = 15
    
    let captureSession = AVCaptureSession()
    let videoOutput = AVCaptureVideoDataOutput()
    let queue = DispatchQueue(label: "net.machinethink.camera-queue")
    
    var lastTimestamp = CMTime()
    var captureDevice: AVCaptureDevice!
    
    public func setUp(sessionPreset: AVCaptureSession.Preset = .medium,
                      completion: @escaping (Bool) -> Void) {
        queue.async {
            let success = self.setUpCamera(sessionPreset: sessionPreset)
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }
    
    func setUpCamera(sessionPreset: AVCaptureSession.Preset) -> Bool {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = sessionPreset
        
        guard let captureDevice = AVCaptureDevice.default(for: AVMediaType.video) else {
            print("Error: no video devices available")
            return false
        }
        
        self.captureDevice = captureDevice
        
        guard let videoInput = try? AVCaptureDeviceInput(device: captureDevice) else {
            print("Error: could not create AVCaptureDeviceInput")
            return false
        }
        
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        }
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = AVLayerVideoGravity.resizeAspect
        previewLayer.connection?.videoOrientation = .portrait
        self.previewLayer = previewLayer
        
        let settings: [String : Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA),
            ]
        
        videoOutput.videoSettings = settings
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        
        // We want the buffers to be in portrait orientation otherwise they are
        // rotated by 90 degrees. Need to set this _after_ addOutput()!
        videoOutput.connection(with: AVMediaType.video)?.videoOrientation = .portrait
        
        captureSession.commitConfiguration()
        return true
    }
    
    public func start() {
        if !captureSession.isRunning {
            captureSession.startRunning()
            self.delegate?.videoCaptureDidStart(self)
        }
    }
    
    public func stop() {
        if captureSession.isRunning {
            captureSession.stopRunning()
            self.delegate?.videoCaptureDidStop(self)
        }
    }
    
    public func zoomIn() {
        self.setZoom(byValue: 0.5)
    }
    
    public func zoomOut() {
        self.setZoom(byValue: -0.5)
    }
    
    private func setZoom(byValue: CGFloat) {
        
        if self.captureDevice.isRampingVideoZoom {
            return
        }
        
        do {
            try self.captureDevice.lockForConfiguration()
            var newZoom = self.captureDevice.videoZoomFactor + byValue
            
            if newZoom < self.captureDevice.minAvailableVideoZoomFactor {
                newZoom = self.captureDevice.minAvailableVideoZoomFactor
            }
            
            if newZoom > self.captureDevice.maxAvailableVideoZoomFactor {
                newZoom = self.captureDevice.maxAvailableVideoZoomFactor
            }
            
            self.captureDevice.ramp(toVideoZoomFactor: newZoom, withRate: 2.0)
            self.captureDevice.unlockForConfiguration()
        } catch {
            print("[VideoCapture]: Error locking configuration")
        }
    }
}

extension VideoCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Because lowering the capture device's FPS looks ugly in the preview,
        // we capture at full speed but only call the delegate at its desired
        // framerate.
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let deltaTime = timestamp - lastTimestamp
        if deltaTime >= CMTimeMake(1, Int32(fps)) {
            lastTimestamp = timestamp
            let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
            delegate?.videoCapture(self, didCaptureVideoFrame: imageBuffer, timestamp: timestamp)
        }
    }
    
    public func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        //print("dropped frame")
    }
}


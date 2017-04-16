//
//  ViewController.swift
//  PicturePerfect
//
//  Created by Gus Silva on 4/12/17.
//  Copyright © 2017 Gus Silva. All rights reserved.
//

import UIKit
import AVFoundation

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    let detector = CIDetector(ofType: CIDetectorTypeFace, context: CIContext(), options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])!

    var videoDataOutput = AVCaptureVideoDataOutput()
    var videoDataOutputQueue: DispatchQueue?
    var imageSet: Bool = false
    
    var cameraPosition: AVCaptureDevicePosition = AVCaptureDevicePosition.front // TODO: Update when switching is added
    var deviceOrientation: UIDeviceOrientation = UIDeviceOrientation.portrait   // TODO: Allow rotation?

    var detectionActive: Bool = false
    
    // The captured image
    var selectedImage = UIImage()
    
    // manages real time capture activity from input devices to create output media (photo/video)
    let captureSession = AVCaptureSession()
    
    // the device we are capturing media from (i.e. front camera of an iPhone 7)
    var captureDevice : AVCaptureDevice?
    
    // view that will let us preview what is being captured from the captureSession
    var previewLayer : AVCaptureVideoPreviewLayer?
    
    // Object used to capture a single photo from our capture device
    let photoOutput = AVCapturePhotoOutput()
    
    @IBOutlet weak var previewHolder: UIView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.videoDataOutputQueue = DispatchQueue(label: "VideoDataOutputQueue")
        
        
        self.captureSession.sessionPreset = AVCaptureSessionPresetHigh
        
        updateCameraSelection()
        setupVideoProcessing()
        setupCameraPreview()
        
        
    }
    
    override func viewDidAppear(_ animated: Bool) {
        self.captureSession.startRunning()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        self.captureSession.stopRunning()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    
    func capture(_ captureOutput: AVCapturePhotoOutput, didFinishProcessingPhotoSampleBuffer photoSampleBuffer: CMSampleBuffer?, previewPhotoSampleBuffer: CMSampleBuffer?, resolvedSettings: AVCaptureResolvedPhotoSettings, bracketSettings: AVCaptureBracketedStillImageSettings?, error: Error?) {
        if let photoSampleBuffer = photoSampleBuffer {
            // students need to add write this part
            let photoData = AVCapturePhotoOutput.jpegPhotoDataRepresentation(forJPEGSampleBuffer: photoSampleBuffer, previewPhotoSampleBuffer: previewPhotoSampleBuffer)
            selectedImage = UIImage(data: photoData!)!
            //            toggleUI(isInPreviewMode: true)
        }
    }
    
    
    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
        if(!detectionActive) {
            return
        }
        if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let ciimage = CIImage(cvImageBuffer: imageBuffer)
            let orientation = getCIDetectorImageOrientation(from: self.deviceOrientation, self.cameraPosition)
            let features = detector.features(in: ciimage, options: [CIDetectorEyeBlink: true, CIDetectorSmile: true, CIDetectorImageOrientation: orientation]) as! [CIFaceFeature]
            for f in features {
                if(f.hasSmile && !f.leftEyeClosed && !f.rightEyeClosed) {
                    // Good picture!
                    detectionActive = false
                    print("Good picture!")
                }
            }
            
        } else {
            print("Error with buffer!")
        }
        
    }
    
    func getCIDetectorImageOrientation(from deviceOrientation: UIDeviceOrientation, _ cameraPos: AVCaptureDevicePosition ) -> Int {
        
        var exifOrientation = 0
        let isUsingFrontFacingCamera: Bool = cameraPos == AVCaptureDevicePosition.front
        switch (deviceOrientation) {
        case UIDeviceOrientation.portraitUpsideDown:  // Device oriented vertically, home button on the top
            exifOrientation = 8;
            break;
        case UIDeviceOrientation.landscapeLeft:       // Device oriented horizontally, home button on the right
            if (isUsingFrontFacingCamera) {
                exifOrientation = 3;
            }
            else {
                exifOrientation = 1;
            }
            break;
        case UIDeviceOrientation.landscapeRight:      // Device oriented horizontally, home button on the left
            if (isUsingFrontFacingCamera) {
                exifOrientation = 1;
            }
            else {
                exifOrientation = 3;
            }
            break;
        default:
            exifOrientation = 6;
            break;
        }
        return exifOrientation
    }
    
    
    func setupVideoProcessing() {
        self.videoDataOutput.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as NSString): NSNumber(value:kCVPixelFormatType_32BGRA)]
        self.videoDataOutput.alwaysDiscardsLateVideoFrames = true
        if(self.captureSession.canAddOutput(self.videoDataOutput)) {
            self.videoDataOutput.setSampleBufferDelegate(self, queue: self.videoDataOutputQueue)
            self.captureSession.addOutput(self.videoDataOutput)
        }
        else {
            print("Failed to setup video output!")
        }
    }
    
    func setupCameraPreview() {
        self.previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
        self.previewLayer?.frame = view.layer.frame
        self.previewHolder.layer.masksToBounds = true
        self.previewHolder.layer.addSublayer(self.previewLayer!)
        self.captureSession.sessionPreset = AVCaptureSessionPresetHigh
        self.captureSession.startRunning()
    }
    
    func updateCameraSelection() {
        
        self.captureSession.beginConfiguration()
        let oldInputs = self.captureSession.inputs
        if let inputs = oldInputs as? [AVCaptureInput] {
            for input in inputs {
                captureSession.removeInput(input)
            }
        }
        if let input = getCamera(forPositon: cameraPosition) {
            // Succeeded, set input and update connection states
            self.captureSession.addInput(input)
            
        } else {
            // Failed, restore old inputs
            if let oldInputs = oldInputs as? [AVCaptureInput] {
                for input in oldInputs {
                    self.captureSession.addInput(input)
                }
            }
        }
        self.captureSession.commitConfiguration()
        
    }
    
    func getCamera(forPositon devicePosition:AVCaptureDevicePosition) -> AVCaptureDeviceInput? {
        if let deviceDiscoverySession = AVCaptureDeviceDiscoverySession.init(deviceTypes: [AVCaptureDeviceType.builtInWideAngleCamera],
                                                                             mediaType: AVMediaTypeVideo,
                                                                             position: AVCaptureDevicePosition.unspecified) {
            
            // Iterate through available devices until we find the user's
            for device in deviceDiscoverySession.devices {
                // only use device if it supports video
                if (device.hasMediaType(AVMediaTypeVideo)) {
                    if (device.position == devicePosition) {
                        captureDevice = device
                        if let input: AVCaptureDeviceInput = try? AVCaptureDeviceInput(device: captureDevice) {
                            if (self.captureSession.canAddInput(input)) {
                                return input
                            }
                        }
                    }
                }
            }
        }
        return nil
    }
    
    @IBAction func moreOptionsPressed(_ sender: UIButton) {
    }
    
    @IBAction func cameraButtonPressed(_ sender: UIButton) {
        detectionActive = true
    }
    
    @IBAction func flipCameraButtonPressed(_ sender: UIButton) {
        if(self.cameraPosition == AVCaptureDevicePosition.front) {
            self.cameraPosition = AVCaptureDevicePosition.back
        } else {
            self.cameraPosition = AVCaptureDevicePosition.front
        }
        updateCameraSelection()
    }
}


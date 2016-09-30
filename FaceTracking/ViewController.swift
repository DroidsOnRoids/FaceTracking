//
//  ViewController.swift
//  AutoCamera
//
//  Created by Pawel Chmiel on 26.09.2016.
//  Copyright © 2016 Pawel Chmiel. All rights reserved.
//

import UIKit
import AVFoundation

class DetailsView : UIView {

    lazy var detailsLabel: UILabel = {
        let detailsLabel = UILabel(frame: CGRect(x: 0, y: 0, width: self.frame.size.width, height: self.frame.size.height))
        detailsLabel.numberOfLines = 0
        detailsLabel.textColor = .white
        detailsLabel.font = UIFont(name: detailsLabel.font.fontName, size: detailsLabel.font.pointSize + 5.0)
        detailsLabel.textAlignment = .left
        return detailsLabel
    }()
    
    func setup() {
        layer.borderColor = UIColor.red.withAlphaComponent(0.7).cgColor
        layer.borderWidth = 5.0
  
        addSubview(detailsLabel)
    }
    
   override var frame : CGRect {
        didSet(newFrame) {
            var detailsFrame = detailsLabel.frame
            detailsFrame = CGRect(x: 0, y: newFrame.size.height , width: newFrame.size.width * 2.0, height: newFrame.size.height / 2.0)
            detailsLabel.frame = detailsFrame
        }
    }
}


class ViewController: UIViewController {

    @IBOutlet weak var shootBtn: UIButton!
    
    var session: AVCaptureSession?
    var stillOutput = AVCaptureStillImageOutput()
    var borderLayer: CAShapeLayer?
   
    let detailsView : DetailsView = {
        let detailsView = DetailsView()
        detailsView.setup()
        return detailsView
    }()
    
    lazy var previewLayer : AVCaptureVideoPreviewLayer = {
        var previewLay = AVCaptureVideoPreviewLayer(session: self.session!)
        previewLay?.videoGravity = AVLayerVideoGravityResizeAspectFill
        return previewLay!
    }()
    
    let faceDetector = CIDetector(ofType: CIDetectorTypeFace, context: nil, options: [CIDetectorAccuracy : CIDetectorAccuracyLow])
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.frame
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        view.layer.addSublayer(previewLayer)
        view.addSubview(detailsView)
        view.bringSubview(toFront: detailsView)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        sessionPrepare()
        session?.startRunning()
    }

}

extension ViewController {

    func sessionPrepare() {
        session = AVCaptureSession()
       
        guard let session = session else { return }
        
        session.sessionPreset = AVCaptureSessionPresetPhoto
        let captureDevice = frontCamera()
       
        guard captureDevice != nil else { return }
        
        do {
            let deviceInput = try AVCaptureDeviceInput(device: captureDevice)
            session.beginConfiguration()
            
            if session.canAddInput(deviceInput) {
                session.addInput(deviceInput)
            }
            
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as NSString) : NSNumber(value: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)]
            
            output.alwaysDiscardsLateVideoFrames = true
        
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
            
            session.commitConfiguration()
            
            let queue = DispatchQueue(label: "output.queue")
            output.setSampleBufferDelegate(self, queue: queue)
            
        } catch {
            print("error with creating AVCaptureDeviceInput")
        }
    }
    
    func frontCamera() -> AVCaptureDevice? {
        let devices = AVCaptureDevice.devices(withMediaType: AVMediaTypeVideo) as? [AVCaptureDevice]
        for device in devices! {
            if device.position == .front {
                return device
            }
        }
        return nil
    }
}

extension ViewController : AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
        let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        let attachments = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, sampleBuffer, kCMAttachmentMode_ShouldPropagate)
        let cgImage = CIImage(cvImageBuffer: pixelBuffer!, options: attachments as! [String : Any]?)
        let options = [CIDetectorImageOrientation: exifOrientation(orientation: UIDevice.current.orientation),CIDetectorSmile: true, CIDetectorEyeBlink: true] as [String : Any]
        let allFeatures = faceDetector?.features(in: cgImage, options: options)
    
        let fdesc = CMSampleBufferGetFormatDescription(sampleBuffer)
        let cleanAperture = CMVideoFormatDescriptionGetCleanAperture(fdesc!, false)
        
        guard let features = allFeatures else { return }
        
        for feature in features {
            if let faceFeature = feature as? CIFaceFeature {
                let faceRect = calculateFaceRect(facePosition: faceFeature.mouthPosition, faceBounds: faceFeature.bounds, clearAperture: cleanAperture)
                update(with: faceRect, text: "has smile :\(faceFeature.hasSmile) \nhas closed left eye :\(faceFeature.leftEyeClosed) \nhas closed right eye :\(faceFeature.rightEyeClosed)")
            }
        }
        
        if features.count == 0 {
            DispatchQueue.main.async {
                self.detailsView.alpha = 0.0
            }
        }
        
    }
    
    func exifOrientation(orientation: UIDeviceOrientation) -> Int {
        switch orientation {
        case .portraitUpsideDown:
            return 8
        case .landscapeLeft:
            return 3
        case .landscapeRight:
            return 1
        default:
            return 6
        }
    }
    
    
    func videoBox(frameSize: CGSize, apertureSize: CGSize) -> CGRect {
    
        let apertureRatio = apertureSize.height / apertureSize.width
        let viewRatio = frameSize.width / frameSize.height
        
        var size = CGSize.zero
     
        if (viewRatio > apertureRatio) {
            size.width = frameSize.width
            size.height = apertureSize.width * (frameSize.width / apertureSize.height)
        } else {
            size.width = apertureSize.height * (frameSize.height / apertureSize.width)
            size.height = frameSize.height
        }
        
        var videoBox = CGRect()
        videoBox.size = size
       
        if (size.width < frameSize.width) {
            videoBox.origin.x = (frameSize.width - size.width) / 2
        } else {
            videoBox.origin.x = (size.width - frameSize.width) / 2
        }
        
        if ( size.height < frameSize.height ) {
            videoBox.origin.y = (frameSize.height - size.height) / 2
        } else {
            videoBox.origin.y = (size.height - frameSize.height) / 2
        }
       
        return videoBox
    
    }

    func calculateFaceRect(facePosition: CGPoint, faceBounds: CGRect, clearAperture: CGRect) -> CGRect {
        
        let parentFrameSize = previewLayer.frame.size;
        let previewBox = videoBox(frameSize: parentFrameSize, apertureSize: clearAperture.size)
        
        var faceRect = faceBounds
        
        var temp = faceRect.size.width
        faceRect.size.width = faceRect.size.height
        faceRect.size.height = temp
        temp = faceRect.origin.x
        faceRect.origin.x = faceRect.origin.y
        faceRect.origin.y = temp
    
        let widthScaleBy = previewBox.size.width / clearAperture.size.height
        let heightScaleBy = previewBox.size.height / clearAperture.size.width
        
        faceRect.size.width *= widthScaleBy;
        faceRect.size.height *= heightScaleBy;
        faceRect.origin.x *= widthScaleBy;
        faceRect.origin.y *= heightScaleBy;
        
        faceRect = faceRect.offsetBy(dx: 0 , dy: previewBox.origin.y);
        let frame = CGRect(x: parentFrameSize.width - faceRect.origin.x - faceRect.size.width / 2.0 - previewBox.origin.x / 2.0, y: faceRect.origin.y, width: faceRect.width, height: faceRect.height)
        return frame
    }
    

}

extension ViewController  {
    
    func update(with faceRect: CGRect, text : String) {
        DispatchQueue.main.async {
            UIView.animate(withDuration: 0.2, animations: {
                self.detailsView.detailsLabel.text = text
                self.detailsView.alpha = 1.0;
                self.detailsView.frame = faceRect
            })
        }
    }
}

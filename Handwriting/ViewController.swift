//
//  ViewController.swift
//  Handwriting
//
//  Created by Mac Mini on 4/5/17.
//  Copyright © 2017 Armonia. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    var network: FFNN!
    let brushWidth: CGFloat = 20
    
    // Drawing state variables
    var lastDrawPoint = CGPoint.zero
    var boundingBox: CGRect?
    var swiped  = false
    var drawing = false
    var timer   = Timer()
    
    // UI Controls
    @IBOutlet weak var canvasContainer : UIView!
    @IBOutlet weak var canvas          : UIImageView!
    @IBOutlet weak var snapshotBox     : UIView!
    @IBOutlet weak var outputContainer : UIView!
    @IBOutlet weak var outputLabel     : UILabel!
    @IBOutlet weak var confidenceLabel : UILabel!
    @IBOutlet weak var imageView       : UIImageView!
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        start()
    }

    func start() {
        // Initial state for snapshotBox and labels
        snapshotBox.alpha              = 0
        snapshotBox.backgroundColor    = UIColor.clear
        snapshotBox.layer.borderColor  = UIColor.green.cgColor
        snapshotBox.layer.borderWidth  = 2
        snapshotBox.layer.cornerRadius = 6
        snapshotBox.layer.opacity      = 0
        outputLabel.text               = ""
        confidenceLabel.text           = ""

        // Load data, start network
        let url = Bundle.main.url(forResource: "handwriting-ffnn", withExtension: nil)!
        self.network = FFNN.fromFile(url: url)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first  else {
            return
        }
        self.swiped = false
        guard canvas.frame.contains(touch.location(in: self.view)) else {
            super.touchesBegan(touches, with: event)
            return
        }
        self.timer.invalidate()
        let location = touch.location(in: canvas)
        if self.boundingBox == nil {
            self.boundingBox = CGRect(x: location.x - self.brushWidth / 2,
                                      y: location.y - self.brushWidth / 2,
                                      width: self.brushWidth,
                                      height: self.brushWidth)
        }
        self.lastDrawPoint = location
        self.drawing = true
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first  else {
            return
        }
        guard self.canvas.frame.contains(touch.location(in: self.view)) else {
            super.touchesMoved(touches, with: event)
            self.swiped = false
            return
        }
        let currentPoint = touch.location(in: canvas)
        if self.swiped {
            self.drawLine(self.lastDrawPoint, toPoint: currentPoint)
        } else {
            self.drawLine(currentPoint, toPoint: currentPoint)
            self.swiped = true
        }
        if currentPoint.x < self.boundingBox!.minX {
            self.updateRect(rect: &self.boundingBox!, minX: currentPoint.x - self.brushWidth - 20, maxX: nil, minY: nil, maxY: nil)
        } else if currentPoint.x > self.boundingBox!.maxX {
            self.updateRect(rect: &self.boundingBox!, minX: nil, maxX: currentPoint.x + self.brushWidth + 20, minY: nil, maxY: nil)
        }
        if currentPoint.y < self.boundingBox!.minY {
            self.updateRect(rect: &self.boundingBox!, minX: nil, maxX: nil, minY: currentPoint.y - self.brushWidth - 20, maxY: nil)
        } else if currentPoint.y > self.boundingBox!.maxY {
            self.updateRect(rect: &self.boundingBox!, minX: nil, maxX: nil, minY: nil, maxY: currentPoint.y + self.brushWidth + 20)
        }
        self.lastDrawPoint = currentPoint
        self.timer.invalidate()
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first  else {
            return
        }
        if canvas.frame.contains(touch.location(in: self.view)) {
            if !self.swiped {
                // Draw dot
                self.drawLine(self.lastDrawPoint, toPoint: self.lastDrawPoint)
            }
        }
        self.timer = Timer.scheduledTimer(timeInterval: 0.4, target: self, selector: #selector(timerExpired), userInfo: nil, repeats: false)
        self.drawing = false
        super.touchesEnded(touches, with: event)
    }
    
    func timerExpired(sender: Timer) {
        self.classifyImage()
        self.boundingBox = nil
    }
    
}


extension Double {
    
    /// Returns the receiver's string representation, truncated to the given number of decimal places.
    /// - parameter decimalPlaces: The maximum number of allowed decimal places
    public func toString(decimalPlaces: Int) -> String {
        let power = pow(10.0, Double(decimalPlaces))
        let rounded = (power * self).rounded() / power
        return "\(rounded)"
    }
    
}



// MARK:- Classification and drawing methods

extension ViewController {
    
    func classifyImage() {
        // Extract and resize image from drawing canvas
        guard let imageArray = self.scanImage() else {
            self.clearCanvas()
            return
        }
        do {
            let output = try self.network.update(inputs: imageArray)
            if let (label, confidence) = self.outputToLabel(output: output) {
                let conf = (confidence * 100).toString(decimalPlaces: 2)
                self.updateOutputLabels(output: "\(label)", confidence: "\(conf)%")
            } else {
                outputLabel.text = "Error"
            }
        } catch {
            print(error)
        }
        
        // Clear the canvas
        self.clearCanvas()
    }
    
    func updateOutputLabels(output: String, confidence: String) {
        UIView.animate(withDuration: 0.1, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0, options: [], animations: { () -> Void in
            self.outputLabel.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
            self.outputLabel.text = output
            self.confidenceLabel.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
            self.confidenceLabel.text = confidence
            }, completion: nil)
        UIView.animate(withDuration: 0.3, delay: 0.1, usingSpringWithDamping: 0.7, initialSpringVelocity: 0, options: [], animations: { () -> Void in
            self.outputLabel.transform = CGAffineTransform.identity
            self.confidenceLabel.transform = CGAffineTransform.identity
            }, completion: nil)
    }
    
    func outputToLabel(output: [Float]) -> (label: Int, confidence: Double)? {
        guard let max = output.max() else {
            return nil
        }
        return (output.index(of: max)!, Double(max / 1.0))
    }
    
    func scanImage() -> [Float]? {
        var pixelsArray = [Float]()
        guard let image = self.canvas.image else {
            return nil
        }
        // Extract drawing from canvas and remove surrounding whitespace
        let croppedImage = self.cropImage(image: image, toRect: self.boundingBox!)
        // Scale character to max 20px in either dimension
        let scaledImage = self.scaleImageToSize(image: croppedImage, maxLength: 20)
        // Center character in 28x28 white box
        let character = self.addBorderToImage(image: scaledImage)
        
        self.imageView.image = character
        
        let pixelData = character.cgImage!.dataProvider!.data
        let data: UnsafePointer<UInt8> = CFDataGetBytePtr(pixelData)
        let bytesPerRow = character.cgImage!.bytesPerRow
        let bytesPerPixel = (character.cgImage!.bitsPerPixel / 8)
        var position = 0
        for _ in 0..<Int(character.size.height) {
            for _ in 0..<Int(character.size.width) {
                let alpha = Float(data[position + 3])
                pixelsArray.append(alpha / 255)
                position += bytesPerPixel
            }
            if position % bytesPerRow != 0 {
                position += (bytesPerRow - (position % bytesPerRow))
            }
        }
        return pixelsArray
    }
    
    func cropImage(image: UIImage, toRect: CGRect) -> UIImage {
        let imageRef = image.cgImage!.cropping(to: toRect)
        let newImage = UIImage(cgImage: imageRef!)
        return newImage
    }
    
    func scaleImageToSize(image: UIImage, maxLength: CGFloat) -> UIImage {
        let size = CGSize(width: min(20 * image.size.width / image.size.height, 20), height: min(20 * image.size.height / image.size.width, 20))
        let newRect = CGRect(x: 0, y: 0, width: size.width, height: size.height).integral
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        let context = UIGraphicsGetCurrentContext()
        context!.interpolationQuality = CGInterpolationQuality.none
        image.draw(in: newRect)
        let newImageRef = context!.makeImage()! as CGImage
        let newImage = UIImage(cgImage: newImageRef, scale: 1.0, orientation: UIImageOrientation.up)
        UIGraphicsEndImageContext()
        return newImage
    }
    
    func addBorderToImage(image: UIImage) -> UIImage {
        UIGraphicsBeginImageContext(CGSize(width: 28, height: 28))
        let white = UIImage(named: "white")!
        white.draw(at: CGPoint.zero)
        image.draw(at: CGPoint(x: (28 - image.size.width) / 2, y: (28 - image.size.height) / 2))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage!
    }
    
    func clearCanvas() {
        // Show snapshot box
        if let box = self.boundingBox {
            self.snapshotBox.frame = box
            self.snapshotBox.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
            UIView.animate(withDuration: 0.1, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0, options: [], animations: { () -> Void in
                self.snapshotBox.alpha = 1
                self.snapshotBox.transform = CGAffineTransform(scaleX: 1.06, y: 1.06)
                }, completion: nil)
            UIView.animate(withDuration: 0.3, delay: 0.1, usingSpringWithDamping: 0.6, initialSpringVelocity: 0, options: [], animations: { () -> Void in
                self.snapshotBox.transform = CGAffineTransform.identity
                }, completion: nil)
        }
        
        UIView.animate(withDuration: 0.1, delay: 0.4, options: [.curveEaseIn], animations: { () -> Void in
            self.canvas.alpha = 0
            self.snapshotBox.alpha = 0
        }) { (Bool) -> Void in
            self.canvas.image = nil
            self.canvas.alpha = 1
        }
    }
    
    func drawLine(_ fromPoint: CGPoint, toPoint: CGPoint) {
        // Begin context
        UIGraphicsBeginImageContext(self.canvas.frame.size)
        let context = UIGraphicsGetCurrentContext()
        // Store current image (lines drawn) in context
        self.canvas.image?.draw(in: CGRect(x: 0, y: 0, width: self.canvas.frame.width, height: self.canvas.frame.height))
        // Append new line to image
        context?.move(to: fromPoint)
        context?.addLine(to: toPoint)
        context?.setLineCap(.round)
        context?.setLineWidth(self.brushWidth)
        context?.setStrokeColor(UIColor.black.cgColor)
        context?.setBlendMode(.normal)
        context?.strokePath()
        // Store modified image back to imageView
        self.canvas.image = UIGraphicsGetImageFromCurrentImageContext()
        // End context
        UIGraphicsEndImageContext()
    }
    
    func updateRect(rect: inout CGRect, minX: CGFloat?, maxX: CGFloat?, minY: CGFloat?, maxY: CGFloat?) {
        rect = CGRect(x: minX ?? rect.minX,
                      y: minY ?? rect.minY,
                      width: (maxX ?? rect.maxX) - (minX ?? rect.minX),
                      height: (maxY ?? rect.maxY) - (minY ?? rect.minY))
    }
    
}


// End

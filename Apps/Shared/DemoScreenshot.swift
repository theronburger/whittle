import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import WhittleCore

enum DemoScreenshot {
    static func record() throws -> ScreenshotRecord {
        let width = 1200, height = 800
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.12, green: 0.17, blue: 0.16, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 240, height: height))
        context.setFillColor(CGColor(red: 0.28, green: 0.65, blue: 0.51, alpha: 1))
        context.fill(CGRect(x: 280, y: 650, width: 350, height: 36))
        for row in 0..<3 {
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 280, y: 100 + row * 160, width: 840, height: 135))
            context.setFillColor(CGColor(red: 0.8, green: 0.83, blue: 0.82, alpha: 1))
            context.fill(CGRect(x: 310, y: 180 + row * 160, width: 300, height: 16))
            context.fill(CGRect(x: 310, y: 145 + row * 160, width: 650, height: 10))
        }
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        guard CGImageDestinationFinalize(destination) else { throw WhittleError.invalidDocument }
        let document = AnnotationDocument(title: "Dashboard feedback", pixelWidth: width, pixelHeight: height)
        return ScreenshotRecord(document: document, originalPNG: data as Data)
    }
}

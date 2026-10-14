#!/usr/bin/env swift
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
func makeIcon(size: Int, mac: Bool) throws {
    let alpha = mac ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: alpha.rawValue)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    NSColor(red: 0.09, green: 0.23, blue: 0.18, alpha: 1).setFill()
    if mac { NSBezierPath(roundedRect: NSRect(x: 90, y: 90, width: 844, height: 844), xRadius: 185, yRadius: 185).fill() }
    else { NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill() }
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 230, y: 700)); path.line(to: NSPoint(x: 350, y: 320))
    path.line(to: NSPoint(x: 515, y: 600)); path.line(to: NSPoint(x: 650, y: 320)); path.line(to: NSPoint(x: 800, y: 700))
    path.lineWidth = 78; path.lineCapStyle = .round; path.lineJoinStyle = .round
    NSColor(red: 0.72, green: 0.92, blue: 0.63, alpha: 1).setStroke(); path.stroke()
    let cut = NSBezierPath()
    cut.move(to: NSPoint(x: 760, y: 225)); cut.line(to: NSPoint(x: 812, y: 265)); cut.lineWidth = 16; cut.lineCapStyle = .round
    NSColor(red: 0.93, green: 0.74, blue: 0.46, alpha: 1).setStroke(); cut.stroke()
    NSGraphicsContext.restoreGraphicsState()
    let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(mac ? "mac-" : "")icon-\(size).png"))
}
try makeIcon(size: 1024, mac: false)
for size in [16, 32, 64, 128, 256, 512, 1024] { try makeIcon(size: size, mac: true) }
var images: [[String: String]] = [["filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"]]
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] { images.append(["filename": "mac-icon-\(size * scale).png", "idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x"]) }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("Contents.json"))

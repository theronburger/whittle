import AppKit
import ScreenCaptureKit

@MainActor
final class RegionCapture {
    private var panels: [NSPanel] = []
    private var completion: ((CGRect?) -> Void)?

    func capture() async throws -> CGImage? {
        if !CGPreflightScreenCaptureAccess() {
            guard CGRequestScreenCaptureAccess() else {
                throw NSError(domain: "Whittle", code: 2, userInfo: [NSLocalizedDescriptionKey: "Allow Whittle in System Settings → Privacy & Security → Screen & System Audio Recording, then capture again."])
            }
        }
        let rectangle: CGRect? = await withCheckedContinuation { continuation in
            completion = { continuation.resume(returning: $0) }
            for screen in NSScreen.screens {
                let panel = CapturePanel(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
                panel.level = .screenSaver
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                let selector = RegionSelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
                selector.onFinish = { [weak self] rect in
                    let global = rect.map { panel.convertToScreen($0) }
                    self?.finish(global)
                }
                panel.contentView = selector
                panels.append(panel)
                panel.makeKeyAndOrderFront(nil)
                panel.makeFirstResponder(selector)
            }
            NSApp.activate()
            NSCursor.crosshair.push()
        }
        guard let rectangle, rectangle.width >= 4, rectangle.height >= 4 else { return nil }
        try await Task.sleep(for: .milliseconds(150))
        let screenHeight = CGDisplayBounds(CGMainDisplayID()).height
        let screenRect = CGRect(x: rectangle.minX, y: screenHeight - rectangle.maxY, width: rectangle.width, height: rectangle.height)
        return try await SCScreenshotManager.captureImage(in: screenRect)
    }

    private func finish(_ rectangle: CGRect?) {
        guard let completion else { return }
        self.completion = nil
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        NSCursor.pop()
        completion(rectangle)
    }
}

private final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class RegionSelectionView: NSView {
    var onFinish: ((CGRect?) -> Void)?
    private var start: CGPoint?
    private var selection = CGRect.zero
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) { start = convert(event.locationInWindow, from: nil) }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let end = convert(event.locationInWindow, from: nil)
        selection = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) { mouseDragged(with: event); onFinish?(selection) }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { onFinish?(nil) } }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()
        if !selection.isEmpty {
            NSGraphicsContext.current?.cgContext.clear(selection)
            NSColor.white.setStroke()
            let outline = NSBezierPath(rect: selection)
            outline.lineWidth = 1.5
            outline.stroke()
        }
        let hint = "Drag to capture · Esc to cancel"
        hint.draw(at: CGPoint(x: bounds.midX - 110, y: bounds.height - 70), withAttributes: [.font: NSFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor.white])
    }
}

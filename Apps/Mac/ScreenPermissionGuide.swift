import AppKit
import SwiftUI

@MainActor
final class ScreenPermissionGuide: NSObject, NSWindowDelegate {
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
    private var panel: NSPanel?
    private var timer: Timer?
    private var deadline = Date.distantPast
    private var settingsAppeared = false

    func open() {
        NSWorkspace.shared.open(Self.settingsURL)
        guard !CGPreflightScreenCaptureAccess(), Bundle.main.bundleURL.pathExtension == "app" else {
            dismiss(); return
        }
        if let panel { panel.orderFrontRegardless(); return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 310, height: 160),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Screen Recording"
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: VStack(alignment: .leading, spacing: 12) {
            Text("Drag this app into the list.").font(.headline)
            DraggableApplication().frame(height: 56)
            Text("Then turn on its switch.").foregroundStyle(.secondary)
        }.padding(20))
        self.panel = panel
        deadline = Date().addingTimeInterval(180)
        settingsAppeared = false
        panel.center()
        updatePosition()
        panel.orderFrontRegardless()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePosition() }
        }
    }

    func dismiss() {
        timer?.invalidate(); timer = nil
        panel?.orderOut(nil); panel = nil
    }

    func windowWillClose(_ notification: Notification) { dismiss() }

    private func updatePosition() {
        guard let panel else { return }
        if CGPreflightScreenCaptureAccess() || Date() >= deadline { dismiss(); return }
        let settings = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        guard let info = windows.first(where: {
            ($0[kCGWindowOwnerPID as String] as? Int32) == settings?.processIdentifier && ($0[kCGWindowLayer as String] as? Int) == 0
        }), let bounds = info[kCGWindowBounds as String] as? NSDictionary,
            let cgFrame = CGRect(dictionaryRepresentation: bounds), let primary = NSScreen.screens.first else {
            if settingsAppeared { dismiss() }
            return
        }
        settingsAppeared = true
        let settingsFrame = NSRect(x: cgFrame.minX, y: primary.frame.maxY - cgFrame.maxY, width: cgFrame.width, height: cgFrame.height)
        let visible = NSScreen.screens.first(where: { $0.frame.intersects(settingsFrame) })?.visibleFrame ?? primary.visibleFrame
        let width = panel.frame.width, height = panel.frame.height
        // Prefer beside Settings; on a narrow display, keep the card at its bottom edge.
        let x = settingsFrame.maxX + width + 12 <= visible.maxX ? settingsFrame.maxX + 12 : settingsFrame.maxX - width - 16
        let y = settingsFrame.minY + 16
        panel.setFrameOrigin(NSPoint(x: min(max(x, visible.minX), visible.maxX - width),
            y: min(max(y, visible.minY), visible.maxY - height)))
    }
}

private struct DraggableApplication: NSViewRepresentable {
    func makeNSView(context: Context) -> ApplicationDragView { ApplicationDragView() }
    func updateNSView(_ view: ApplicationDragView, context: Context) {}
}

final class ApplicationDragView: NSView, NSDraggingSource {
    private let icon = NSWorkspace.shared.icon(forFile: Bundle.main.bundleURL.path)

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Drag Whittle into Screen Recording permissions")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        icon.draw(in: NSRect(x: 0, y: 4, width: 48, height: 48))
        ("Whittle" as NSString).draw(at: NSPoint(x: 60, y: 20), withAttributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor.labelColor
        ])
    }
    override func mouseDown(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: Self.dragURL as NSURL)
        item.setDraggingFrame(NSRect(x: 0, y: 4, width: 48, height: 48), contents: icon)
        beginDraggingSession(with: [item], event: event, source: self).animatesToStartingPositionsOnCancelOrFail = true
    }
    static var dragURL: URL { Bundle.main.bundleURL }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}

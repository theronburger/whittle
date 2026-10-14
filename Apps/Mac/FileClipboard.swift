import AppKit
import SwiftUI
import WhittleCore

enum FileClipboard {
    static func write(_ files: ExportedFiles, to pasteboard: NSPasteboard = .general) throws {
        pasteboard.clearContents()
        guard pasteboard.writeObjects(files.urls.map { $0 as NSURL }) else {
            throw NSError(domain: "Whittle", code: 1, userInfo: [NSLocalizedDescriptionKey: "Couldn’t copy the feedback files."])
        }
    }
}

struct FeedbackFileDrag: NSViewRepresentable {
    let files: ExportedFiles
    func makeNSView(context: Context) -> FeedbackDragView { FeedbackDragView(files: files) }
    func updateNSView(_ view: FeedbackDragView, context: Context) { view.files = files }
}

final class FeedbackDragView: NSView, NSDraggingSource {
    var files: ExportedFiles
    init(files: ExportedFiles) { self.files = files; super.init(frame: .zero); toolTip = "Drag the annotated image and notes into your agent" }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func mouseDragged(with event: NSEvent) {
        let items = files.urls.enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            item.setDraggingFrame(NSRect(x: index * 24, y: 0, width: 48, height: 48), contents: NSWorkspace.shared.icon(forFile: url.path))
            return item
        }
        beginDraggingSession(with: items, event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}

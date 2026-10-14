import Testing
import UIKit
import WhittleCore

@MainActor
struct CanvasHistoryTests {
    @Test func untouchedInkDoesNotConsumeAnnotationUndo() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = try ScreenshotLibrary(directory: directory)
        let document = AnnotationDocument(title: "History", pixelWidth: 400, pixelHeight: 300)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300)).image { _ in }
        try library.receive(ScreenshotRecord(document: document, originalPNG: image.pngData()!))
        let view = CanvasWorkspaceView()
        let controller = CanvasController()
        view.onEdit = { library.edit(document.id, $0) }
        view.configure(document: document, original: image, controller: controller)

        library.edit(document.id) { $0.arrows.append(.init(start: .init(x: 0.2, y: 0.2), end: .init(x: 0.8, y: 0.8))) }
        view.configure(document: try #require(library.selected), original: image, controller: controller)
        view.commitInk()
        library.undo()

        #expect(library.selected?.arrows.isEmpty == true)
        #expect(library.canUndo == false)
        #expect(library.canRedo == true)
    }
}

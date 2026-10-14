import PencilKit
import SnapshotTesting
import Testing
import UIKit
import WhittleCore

@MainActor
struct AnnotationRendererTests {
    @Test func exportKeepsOriginalDimensionsAndRendersInkArrowsAndNotes() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let original = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600), format: format).image { context in
            UIColor(white: 0.96, alpha: 1).setFill(); context.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
            UIColor.darkGray.setFill(); context.fill(CGRect(x: 60, y: 80, width: 680, height: 80))
            UIColor.white.setFill(); context.fill(CGRect(x: 60, y: 210, width: 320, height: 260))
        }
        var document = AnnotationDocument(title: "Renderer fixture", pixelWidth: 800, pixelHeight: 600)
        document.notes = [.init(anchor: .init(x: 0.5, y: 0.5), position: .init(x: 0.6, y: 0.7), text: "Give this card more breathing room.")]
        document.arrows = [.init(start: .init(x: 0.8, y: 0.3), end: .init(x: 0.45, y: 0.45))]
        let point = PKStrokePoint(location: CGPoint(x: 100, y: 300), timeOffset: 0, size: CGSize(width: 6, height: 6), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        let end = PKStrokePoint(location: CGPoint(x: 320, y: 300), timeOffset: 0.2, size: CGSize(width: 6, height: 6), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        document.ink = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .systemRed), path: PKStrokePath(controlPoints: [point, end], creationDate: Date(timeIntervalSince1970: 0)))]).dataRepresentation()
        let image = try AnnotationRenderer.image(document: document, original: original)
        #expect(image.cgImage?.width == 800)
        #expect(image.cgImage?.height == 600)
        assertSnapshot(of: image, as: .image, named: "annotated-feedback")
    }

    @Test func emptyAnnotationsLeaveOriginalPixelsUnchanged() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let original = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 80), format: format).image { context in
            UIColor.orange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 100, height: 80))
        }
        let document = AnnotationDocument(title: "Original", pixelWidth: 100, pixelHeight: 80)
        let image = try AnnotationRenderer.image(document: document, original: original)
        assertSnapshot(of: image, as: .image, named: "unaltered-original")
    }
}

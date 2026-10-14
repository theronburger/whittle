import PencilKit
import UIKit
import WhittleCore

enum AnnotationRenderer {
    static func logicalSize(for document: AnnotationDocument) -> CGSize {
        let width = min(1400, CGFloat(document.pixelWidth))
        return CGSize(width: width, height: width * CGFloat(document.pixelHeight) / CGFloat(document.pixelWidth))
    }

    static func image(document: AnnotationDocument, original: UIImage) throws -> UIImage {
        try document.validate()
        let size = CGSize(width: document.pixelWidth, height: document.pixelHeight)
        let logical = logicalSize(for: document)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let drawing = document.ink.isEmpty ? PKDrawing() : try PKDrawing(data: document.ink)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            original.draw(in: CGRect(origin: .zero, size: size))
            if !drawing.strokes.isEmpty { drawing.image(from: CGRect(origin: .zero, size: logical), scale: size.width / logical.width).draw(in: CGRect(origin: .zero, size: size)) }
            context.cgContext.scaleBy(x: size.width / logical.width, y: size.height / logical.height)
            drawAnnotations(document, size: logical)
        }
    }

    static func drawAnnotations(_ document: AnnotationDocument, size: CGSize) {
        for arrow in document.arrows { drawArrow(arrow, size: size) }
        for (index, note) in document.notes.enumerated() { drawNote(note, number: index + 1, size: size) }
    }

    static func noteRect(_ note: AnnotationNote, size: CGSize) -> CGRect {
        let width = min(238, size.width * 0.8)
        let text = note.text.isEmpty ? "Add your feedback…" : note.text
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 15, weight: .medium)]
        let textHeight = (text as NSString).boundingRect(with: CGSize(width: width - 32, height: 180), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil).height
        let height = max(68, min(220, ceil(textHeight) + 46))
        let x = min(max(8, CGFloat(note.position.x) * size.width), max(8, size.width - width - 8))
        let y = min(max(8, CGFloat(note.position.y) * size.height), max(8, size.height - height - 8))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func drawArrow(_ arrow: AnnotationArrow, size: CGSize) {
        let start = CGPoint(x: arrow.start.x * size.width, y: arrow.start.y * size.height)
        let end = CGPoint(x: arrow.end.x * size.width, y: arrow.end.y * size.height)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let path = UIBezierPath()
        path.move(to: start); path.addLine(to: end)
        path.move(to: CGPoint(x: end.x - 16 * cos(angle - .pi / 6), y: end.y - 16 * sin(angle - .pi / 6)))
        path.addLine(to: end)
        path.addLine(to: CGPoint(x: end.x - 16 * cos(angle + .pi / 6), y: end.y - 16 * sin(angle + .pi / 6)))
        path.lineWidth = 4
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        UIColor(arrow.color.color).setStroke()
        path.stroke()
    }

    private static func drawNote(_ note: AnnotationNote, number: Int, size: CGSize) {
        let rect = noteRect(note, size: size)
        let anchor = CGPoint(x: note.anchor.x * size.width, y: note.anchor.y * size.height)
        let tint = UIColor(note.color.color)
        if hypot(anchor.x - rect.minX, anchor.y - rect.minY) > 32 {
            let leader = UIBezierPath()
            leader.move(to: anchor); leader.addLine(to: CGPoint(x: rect.minX + 16, y: rect.minY + 16))
            leader.lineWidth = 2; tint.setStroke(); leader.stroke()
            tint.setFill()
            UIBezierPath(ovalIn: CGRect(x: anchor.x - 5, y: anchor.y - 5, width: 10, height: 10)).fill()
        }
        let context = UIGraphicsGetCurrentContext()
        context?.saveGState()
        context?.setShadow(offset: CGSize(width: 0, height: 3), blur: 10, color: UIColor.black.withAlphaComponent(0.18).cgColor)
        tint.withAlphaComponent(0.98).setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 12).fill()
        context?.restoreGState()
        let ink = UIColor(red: 0.1, green: 0.13, blue: 0.13, alpha: 1)
        ("\(number)" as NSString).draw(at: CGPoint(x: rect.minX + 14, y: rect.minY + 9), withAttributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold), .foregroundColor: ink.withAlphaComponent(0.65)])
        let text = note.text.isEmpty ? "Add your feedback…" : note.text
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        (text as NSString).draw(in: CGRect(x: rect.minX + 14, y: rect.minY + 30, width: rect.width - 28, height: rect.height - 38), withAttributes: [.font: UIFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: ink, .paragraphStyle: paragraph])
    }
}

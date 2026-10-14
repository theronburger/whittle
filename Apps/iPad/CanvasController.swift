import Observation
import PencilKit
import SwiftUI
import UIKit
import WhittleCore

enum CanvasTool: String { case pen, eraser, arrow, select }

@MainActor @Observable
final class CanvasController {
    var tool: CanvasTool = .pen
    var color: AnnotationColor = .coral
    var drawWithFinger = false
    var lineWidth: CGFloat = 4
    @ObservationIgnored weak var view: CanvasWorkspaceView?
    var onEditNote: ((UUID) -> Void)?

    func resetView() { view?.resetViewport() }
    func flushInk() { view?.commitInk() }
    func addNote(at point: CGPoint) { view?.addNote(at: point) }
}

struct AnnotationCanvas: UIViewRepresentable {
    let document: AnnotationDocument
    let original: UIImage
    let controller: CanvasController
    let onEdit: ((inout AnnotationDocument) -> Void) -> Void

    func makeUIView(context: Context) -> CanvasWorkspaceView {
        let view = CanvasWorkspaceView()
        controller.view = view
        return view
    }

    func updateUIView(_ view: CanvasWorkspaceView, context: Context) {
        controller.view = view
        view.onEdit = onEdit
        view.onEditNote = controller.onEditNote
        view.configure(document: document, original: original, controller: controller)
    }
}

final class CanvasWorkspaceView: UIView, UIGestureRecognizerDelegate, PKCanvasViewDelegate {
    private let documentView = UIView()
    private let imageView = UIImageView()
    private let inkView = PKCanvasView()
    private let annotations = AnnotationOverlayView()
    private var document: AnnotationDocument?
    private var appliedInk = Data()
    private var fittingScale: CGFloat = 1
    private var zoom: CGFloat = 1
    private var rotation: CGFloat = 0
    private var offset = CGPoint.zero
    private var configuring = false
    private var lastSize = CGSize.zero
    var onEdit: (((inout AnnotationDocument) -> Void) -> Void)?
    var onEditNote: ((UUID) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(WhittleTheme.canvas)
        clipsToBounds = true
        accessibilityIdentifier = "annotationCanvas"
        isAccessibilityElement = true
        accessibilityLabel = "Annotation canvas"
        addSubview(documentView)
        documentView.backgroundColor = .white
        documentView.layer.shadowColor = UIColor.black.cgColor
        documentView.layer.shadowOpacity = 0.3
        documentView.layer.shadowRadius = 28
        documentView.addSubview(imageView)
        documentView.addSubview(inkView)
        documentView.addSubview(annotations)
        inkView.backgroundColor = .clear
        inkView.isOpaque = false
        inkView.isScrollEnabled = false
        inkView.delegate = self
        annotations.onEdit = { [weak self] edit in self?.onEdit?(edit) }
        annotations.onEditNote = { [weak self] id in self?.onEditNote?(id) }
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:)))
        let rotate = UIRotationGestureRecognizer(target: self, action: #selector(rotate(_:)))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
        pan.minimumNumberOfTouches = 2
        for gesture in [pinch, rotate, pan] { gesture.delegate = self; addGestureRecognizer(gesture) }
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(resetViewport))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func configure(document: AnnotationDocument, original: UIImage, controller: CanvasController) {
        let changedDocument = self.document?.id != document.id
        self.document = document
        imageView.image = original
        let size = AnnotationRenderer.logicalSize(for: document)
        documentView.bounds = CGRect(origin: .zero, size: size)
        for view in [imageView, inkView, annotations] { view.frame = documentView.bounds }
        inkView.contentSize = size
        if changedDocument || appliedInk != document.ink {
            configuring = true
            inkView.drawing = (try? PKDrawing(data: document.ink)) ?? PKDrawing()
            appliedInk = document.ink
            configuring = false
        }
        inkView.drawingPolicy = controller.drawWithFinger ? .anyInput : .pencilOnly
        inkView.tool = controller.tool == .eraser ? PKEraserTool(.vector) : PKInkingTool(.pen, color: UIColor(controller.color.color), width: controller.lineWidth)
        inkView.isUserInteractionEnabled = controller.tool == .pen || controller.tool == .eraser
        annotations.document = document
        annotations.tool = controller.tool
        annotations.color = controller.color
        annotations.setNeedsDisplay()
        accessibilityValue = "\(document.notes.count) notes, \(document.arrows.count) arrows"
        if changedDocument { resetViewport() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if lastSize != bounds.size { lastSize = bounds.size; resetViewport() }
    }

    @objc func resetViewport() {
        guard documentView.bounds.width > 0, bounds.width > 0 else { return }
        fittingScale = min((bounds.width - 80) / documentView.bounds.width, (bounds.height - 130) / documentView.bounds.height)
        fittingScale = max(0.01, fittingScale)
        zoom = 1; rotation = 0; offset = .zero
        updateTransform()
    }

    func addNote(at point: CGPoint) {
        guard document != nil else { return }
        let local = documentView.convert(point, from: self)
        guard documentView.bounds.contains(local) else { return }
        let anchor = CanvasPoint(x: local.x / documentView.bounds.width, y: local.y / documentView.bounds.height)
        let note = AnnotationNote(anchor: anchor)
        onEdit? { $0.notes.append(note) }
        onEditNote?(note.id)
    }

    func commitInk() {
        guard !configuring, document != nil else { return }
        let data = inkView.drawing.strokes.isEmpty ? Data() : inkView.drawing.dataRepresentation()
        guard data != appliedInk else { return }
        appliedInk = data
        onEdit? { $0.ink = data }
    }

    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) { commitInk() }

    @objc private func pinch(_ gesture: UIPinchGestureRecognizer) {
        zoom = min(12, max(0.4, zoom * gesture.scale)); gesture.scale = 1
        updateTransform()
    }
    @objc private func rotate(_ gesture: UIRotationGestureRecognizer) { rotation += gesture.rotation; gesture.rotation = 0; updateTransform() }
    @objc private func pan(_ gesture: UIPanGestureRecognizer) {
        let delta = gesture.translation(in: self)
        offset.x += delta.x; offset.y += delta.y
        gesture.setTranslation(.zero, in: self)
        updateTransform()
    }
    private func updateTransform() {
        documentView.center = CGPoint(x: bounds.midX + offset.x, y: bounds.midY - 25 + offset.y)
        documentView.transform = CGAffineTransform(rotationAngle: rotation).scaledBy(x: fittingScale * zoom, y: fittingScale * zoom)
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
}

private final class AnnotationOverlayView: UIView {
    var document: AnnotationDocument?
    var tool: CanvasTool = .pen
    var color: AnnotationColor = .coral
    var onEdit: (((inout AnnotationDocument) -> Void) -> Void)?
    var onEditNote: ((UUID) -> Void)?
    private var preview: AnnotationArrow?
    private var movingID: UUID?
    private var initialPosition = CGPoint.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        let pan = UIPanGestureRecognizer(target: self, action: #selector(drag(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap(_:))))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        tool == .arrow || note(at: point) != nil
    }

    override func draw(_ rect: CGRect) {
        guard let document else { return }
        AnnotationRenderer.drawAnnotations(document, size: bounds.size)
        if let preview { AnnotationRenderer.drawArrow(preview, size: bounds.size) }
    }

    private func note(at point: CGPoint) -> AnnotationNote? {
        document?.notes.reversed().first { AnnotationRenderer.noteRect($0, size: bounds.size).contains(point) }
    }

    @objc private func tap(_ gesture: UITapGestureRecognizer) {
        if let note = note(at: gesture.location(in: self)) { onEditNote?(note.id) }
    }

    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: self)
        let normalized = CanvasPoint(x: point.x / bounds.width, y: point.y / bounds.height)
        switch gesture.state {
        case .began:
            if let note = note(at: point) {
                movingID = note.id
                initialPosition = CGPoint(x: note.position.x, y: note.position.y)
            } else if tool == .arrow { preview = .init(start: normalized, end: normalized, color: color) }
        case .changed:
            if var preview { preview.end = normalized; self.preview = preview; setNeedsDisplay() }
            if let id = movingID, let index = document?.notes.firstIndex(where: { $0.id == id }) {
                let delta = gesture.translation(in: self)
                document?.notes[index].position = CanvasPoint(x: initialPosition.x + delta.x / bounds.width, y: initialPosition.y + delta.y / bounds.height)
                setNeedsDisplay()
            }
        case .ended:
            if var preview {
                preview.end = normalized
                if hypot(preview.end.x - preview.start.x, preview.end.y - preview.start.y) > 0.005 { onEdit? { $0.arrows.append(preview) } }
            }
            if let id = movingID, let position = document?.notes.first(where: { $0.id == id })?.position {
                onEdit? { document in if let index = document.notes.firstIndex(where: { $0.id == id }) { document.notes[index].position = position } }
            }
            preview = nil; movingID = nil; setNeedsDisplay()
        case .cancelled, .failed: preview = nil; movingID = nil; setNeedsDisplay()
        default: break
        }
    }
}

import PencilKit
import SwiftUI
import WhittleCore

struct PadWorkspaceView: View {
    @Bindable var model: PadModel
    @State private var controller = CanvasController()
    @State private var editingNote: UUID?
    @State private var image: UIImage?
    @State private var imageID: UUID?
    @State private var dragPoint: CGPoint?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            VStack(spacing: 0) {
                header
                if let document = model.library.selected, imageID == document.id, let image {
                    workspace(document: document, image: image)
                } else {
                    emptyWorkspace
                }
            }
            .background(WhittleTheme.canvas)
            .toolbar(.hidden, for: .navigationBar)
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $model.showingPairing) { PadPairingView(model: model) }
        .sheet(isPresented: Binding(get: { editingNote != nil }, set: { if !$0 { editingNote = nil } })) {
            if let id = editingNote, let document = model.library.selected {
                NoteEditor(library: model.library, documentID: document.id, noteID: id)
            }
        }
        .task(id: model.library.selectedID) {
            controller.flushInk()
            if let document = model.library.selected, let data = model.library.original(document.id) {
                image = UIImage(data: data); imageID = document.id
            } else { image = nil; imageID = nil }
            controller.onEditNote = { editingNote = $0 }
        }
        .onChange(of: scenePhase) { _, _ in controller.flushInk() }
        .alert("Whittle", isPresented: Binding(get: { model.error != nil || model.library.error != nil }, set: { if !$0 { model.error = nil; model.library.error = nil } })) {
            Button("OK") { model.error = nil; model.library.error = nil }
        } message: { Text(model.error ?? model.library.error ?? "") }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "pencil.tip.crop.circle.fill").font(.title).foregroundStyle(WhittleTheme.accent)
                Text("Whittle").font(.title2.weight(.bold))
                Spacer()
            }.padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 18)
            HStack {
                Text("SCREENSHOTS").font(.caption2.weight(.semibold)).tracking(1.3).foregroundStyle(.secondary)
                Spacer()
                Text("\(model.library.documents.count)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
            }.padding(.horizontal, 20).padding(.bottom, 8)
            List(selection: Binding(get: { model.library.selectedID }, set: { controller.flushInk(); model.library.selectedID = $0 })) {
                ForEach(model.library.documents) { document in
                    ScreenshotRow(document: document, library: model.library)
                        .tag(document.id)
                        .listRowSeparator(.hidden)
                        .listRowBackground(model.library.selectedID == document.id ? WhittleTheme.accent.opacity(0.12) : Color.clear)
                        .accessibilityIdentifier("screenshot-\(document.id)")
                }
            }.listStyle(.sidebar).scrollContentBackground(.hidden)
            Spacer(minLength: 0)
            Divider()
            Button { model.showingPairing = true } label: {
                HStack {
                    ConnectionBadge(connected: model.connected, text: model.connectionText)
                    Spacer()
                    Image(systemName: "link").font(.caption).foregroundStyle(.secondary)
                }.padding(18)
            }.buttonStyle(.plain).accessibilityLabel("Connection Settings").accessibilityIdentifier("connectionSettings")
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation { columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly }
            } label: { Image(systemName: "sidebar.left").frame(width: 32, height: 40) }.foregroundStyle(.white.opacity(0.65))
                .accessibilityLabel("Toggle Sidebar")
            VStack(alignment: .leading, spacing: 3) {
                Text(model.library.selected?.title ?? "A little feedback goes a long way.").font(.headline).lineLimit(1)
                if let document = model.library.selected {
                    Text("\(document.pixelWidth) × \(document.pixelHeight)  ·  \(document.notes.count) notes")
                        .font(.caption).foregroundStyle(.white.opacity(0.45)).accessibilityIdentifier("annotationSummary")
                }
            }.foregroundStyle(.white)
            Spacer()
            if let status = model.copyStatus { Text(status).font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(1).accessibilityIdentifier("copyStatus") }
            CircleIconButton(title: "Reset Pan, Zoom and Rotation", symbol: "arrow.counterclockwise") { controller.resetView() }
                .accessibilityIdentifier("resetViewport")
            CircleIconButton(title: "Copy Feedback to Mac", symbol: "doc.on.doc") { copyFeedback() }
                .accessibilityIdentifier("copyFeedback").disabled(model.library.selected == nil)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(WhittleTheme.canvas)
    }

    private func workspace(document: AnnotationDocument, image: UIImage) -> some View {
        ZStack(alignment: .bottom) {
            AnnotationCanvas(document: document, original: image, controller: controller) { edit in model.library.edit(document.id, edit) }
            if let dragPoint {
                Image(systemName: "note.text").font(.title).padding(16)
                    .foregroundStyle(.black).background(AnnotationColor.amber.color, in: RoundedRectangle(cornerRadius: 14))
                    .position(dragPoint).allowsHitTesting(false)
            }
            annotationToolbar.padding(.bottom, 22)
        }.coordinateSpace(name: "workspace")
    }

    private var annotationToolbar: some View {
        HStack(spacing: 6) {
            toolButton("Pen", symbol: "pencil.tip", tool: .pen)
            toolButton("Eraser", symbol: "eraser", tool: .eraser)
            toolButton("Arrow", symbol: "arrow.up.right", tool: .arrow)
            Image(systemName: "note.text").font(.system(size: 21)).frame(width: 48, height: 48)
                .foregroundStyle(AnnotationColor.amber.color)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("workspace"))
                    .onChanged { dragPoint = $0.location }
                    .onEnded { controller.addNote(at: $0.location); dragPoint = nil })
                .accessibilityLabel("Drag a Note").accessibilityIdentifier("dragNote")
            Divider().frame(height: 26).padding(.horizontal, 4)
            Menu {
                ForEach(AnnotationColor.allCases, id: \.rawValue) { color in Button(color.rawValue.capitalized, systemImage: "circle.fill") { controller.color = color } }
                Divider()
                ForEach([2.0, 4.0, 8.0], id: \.self) { width in Button("\(Int(width)) pt") { controller.lineWidth = width } }
            } label: { Circle().fill(controller.color.color).frame(width: 22, height: 22).frame(width: 42, height: 48) }
                .accessibilityLabel("Ink Color and Width")
            Button { controller.flushInk(); model.library.undo() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 42, height: 48) }
                .disabled(!model.library.canUndo).accessibilityLabel("Undo").accessibilityIdentifier("undo")
            Button { controller.flushInk(); model.library.redo() } label: { Image(systemName: "arrow.uturn.forward").frame(width: 42, height: 48) }
                .disabled(!model.library.canRedo).accessibilityLabel("Redo")
            Menu {
                Toggle("Draw with Finger", isOn: $controller.drawWithFinger)
                Button("Edit Notes", systemImage: "list.bullet") { if let id = model.library.selected?.notes.first?.id { editingNote = id } }
            } label: { Image(systemName: "ellipsis").frame(width: 38, height: 48) }.accessibilityLabel("More Drawing Options")
        }
        .buttonStyle(.plain).foregroundStyle(.primary)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 5)
    }

    private func toolButton(_ title: String, symbol: String, tool: CanvasTool) -> some View {
        Button { controller.tool = tool } label: {
            Image(systemName: symbol).font(.system(size: 21)).frame(width: 48, height: 48)
                .background(controller.tool == tool ? WhittleTheme.accent.opacity(0.18) : Color.clear, in: Circle())
                .foregroundStyle(controller.tool == tool ? WhittleTheme.accent : .primary)
        }.accessibilityLabel(title).accessibilityIdentifier("tool-\(tool.rawValue)")
    }

    private var emptyWorkspace: some View {
        VStack(spacing: 18) {
            Image(systemName: "pencil.and.scribble").font(.system(size: 62, weight: .ultraLight)).foregroundStyle(WhittleTheme.accent)
            Text("See it. Mark it. Send it.").font(.system(size: 30, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            Text("Capture a region with Whittle on your Mac.\nIt’ll land here, ready for your feedback.")
                .font(.body).foregroundStyle(.white.opacity(0.5)).multilineTextAlignment(.center)
            if !model.connected { Button("Pair Your Mac", systemImage: "qrcode.viewfinder") { model.showingPairing = true }.buttonStyle(.borderedProminent).padding(.top, 8) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func copyFeedback() {
        controller.flushInk()
        guard let document = model.library.selected, let data = model.library.original(document.id), let original = UIImage(data: data) else { return }
        do {
            let rendered = try AnnotationRenderer.image(document: document, original: original)
            guard let png = rendered.pngData() else { throw WhittleError.invalidDocument }
            model.copyFeedback(document: document, png: png)
        } catch { model.error = error.localizedDescription }
    }
}

private struct ScreenshotRow: View {
    let document: AnnotationDocument
    let library: ScreenshotLibrary
    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let thumbnail { Image(uiImage: thumbnail).resizable().scaledToFit() }
                else { Rectangle().fill(.quaternary) }
            }.frame(height: 100).frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(document.title).font(.callout.weight(.medium)).lineLimit(1)
            HStack {
                Text(document.capturedAt, style: .time)
                Spacer()
                if !document.notes.isEmpty { Label("\(document.notes.count)", systemImage: "note.text") }
            }.font(.caption2).foregroundStyle(.secondary)
        }.padding(.vertical, 8)
            .task(id: document.id) { if let data = library.original(document.id) { thumbnail = UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 440, height: 240)) } }
    }
}

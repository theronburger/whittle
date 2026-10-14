import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MacMenuView: View {
    @Bindable var model: MacModel
    var onCapture: () -> Void
    @Environment(\.openWindow) private var openWindow
    @State private var dropTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "pencil.tip.crop.circle.fill").font(.title2).foregroundStyle(WhittleTheme.accent)
                Text("Whittle").font(.title3.bold())
                Spacer()
                Button { openWindow(id: "settings"); NSApp.activate() } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.plain).help("Pairing & Settings")
            }
            ConnectionBadge(connected: model.connected, text: model.peerName)
            HStack {
                Button(action: onCapture) { Label("Capture Region", systemImage: "viewfinder").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(WhittleTheme.accent).disabled(model.isCapturing)
                Button { model.importClipboard() } label: { Image(systemName: "doc.on.clipboard") }
                    .help("Paste Screenshot")
            }
            if let files = model.latestExport {
                VStack(alignment: .leading, spacing: 8) {
                    Text("FEEDBACK READY").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    HStack {
                        Image(systemName: "photo.on.rectangle.angled").font(.title2).foregroundStyle(WhittleTheme.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.latestTitle).font(.callout.weight(.medium)).lineLimit(1)
                            Text("Image + text notes · drag into your agent").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { model.copyLatest() } label: { Image(systemName: "doc.on.doc") }.help("Copy Both Files")
                    }
                    .padding(12).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(FeedbackFileDrag(files: files).padding(.trailing, 36))
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "ipad.and.arrow.forward").font(.system(size: 28)).foregroundStyle(.secondary)
                    Text(model.connected ? "Capture something. Make your point." : "Pair your iPad to get started.").font(.callout)
                    Text("Or drop an image here").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 22)
                    .background(dropTarget ? WhittleTheme.accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
            }
            if let error = model.error ?? model.library.error {
                Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                if model.needsScreenPermission {
                    Button("Open Screen Recording Settings…") { model.openScreenPermissions() }
                }
            }
            Divider()
            HStack {
                Text("Fast screen annotation for agentic dev.").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain).font(.caption)
            }
        }
        .padding(20).frame(width: 360)
        .onDrop(of: [UTType.fileURL.identifier, UTType.png.identifier], isTargeted: $dropTarget) { providers in
            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                        let url = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                        if let url { Task { @MainActor in model.importFiles([url]) } }
                    }
                } else {
                    provider.loadDataRepresentation(forTypeIdentifier: UTType.png.identifier) { data, _ in
                        if let data { Task { @MainActor in do { try model.addScreenshot(data, title: "Dropped screenshot") } catch { model.error = error.localizedDescription } } }
                    }
                }
            }
            return !providers.isEmpty
        }
    }
}

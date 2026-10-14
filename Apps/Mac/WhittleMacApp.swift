import AppKit
import KeyboardShortcuts
import SwiftUI

@main @MainActor
struct WhittleMacApp: App {
    @State private var model: MacModel?
    private let startupError: String?
    private let showSettingsOnLaunch: Bool

    init() {
        showSettingsOnLaunch = AppDirectories.isUITesting || ProcessInfo.processInfo.arguments.contains("--show-settings") || !UserDefaults.standard.bool(forKey: "hasLaunched")
        if !AppDirectories.isTesting { UserDefaults.standard.set(true, forKey: "hasLaunched") }
        do {
            let model = try MacModel()
            _model = State(initialValue: model)
            startupError = nil
            if !AppDirectories.isTesting {
                KeyboardShortcuts.onKeyUp(for: .captureRegion) {
                    Task { @MainActor in await Self.captureRegion(model) }
                }
                KeyboardShortcuts.onKeyUp(for: .pasteScreenshot) { model.importClipboard() }
            }
        } catch {
            _model = State(initialValue: nil)
            startupError = error.localizedDescription
        }
    }

    var body: some Scene {
        MenuBarExtra("Whittle", systemImage: "pencil.tip.crop.circle") {
            if let model {
                MacMenuView(model: model, onCapture: { Task { await Self.captureRegion(model) } })
            } else {
                Text(startupError ?? "Starting Whittle…").padding().frame(width: 320)
            }
        }
        .menuBarExtraStyle(.window)

        Window("Whittle", id: "settings") {
            if let model { MacSettingsView(model: model) }
            else { Text(startupError ?? "Starting…").padding() }
        }
        .defaultSize(width: 480, height: 600)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(showSettingsOnLaunch ? .presented : .suppressed)
    }

    private static func captureRegion(_ model: MacModel) async {
        guard !model.isCapturing else { return }
        model.isCapturing = true
        model.needsScreenPermission = false
        defer { model.isCapturing = false }
        let capture = RegionCapture()
        do {
            guard let image = try await capture.capture() else { return }
            let bitmap = NSBitmapImageRep(cgImage: image)
            if let data = bitmap.representation(using: .png, properties: [:]) {
                try model.addScreenshot(data, title: Date().formatted(date: .abbreviated, time: .shortened))
            }
        } catch {
            model.needsScreenPermission = !CGPreflightScreenCaptureAccess()
            model.error = error.localizedDescription
        }
    }
}

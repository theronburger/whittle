import SwiftUI

@main @MainActor
struct WhittlePadApp: App {
    @State private var model: PadModel?
    private let startupError: String?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do { _model = State(initialValue: try PadModel()); startupError = nil }
        catch { _model = State(initialValue: nil); startupError = error.localizedDescription }
    }

    var body: some Scene {
        WindowGroup {
            if let model {
                PadWorkspaceView(model: model)
                    .tint(WhittleTheme.accent)
                    .onOpenURL { url in
                        if url.host == "scan" { model.showingPairing = true; model.scanning = true }
                        else { model.pair(code: url.absoluteString) }
                    }
                    .onChange(of: scenePhase) { _, phase in model.setActive(phase == .active) }
            } else {
                ContentUnavailableView("Whittle couldn’t open its library", systemImage: "externaldrive.badge.exclamationmark", description: Text(startupError ?? "Please try again."))
            }
        }
    }
}

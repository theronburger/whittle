import AppKit
import CoreImage.CIFilterBuiltins
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct MacSettingsView: View {
    @Bindable var model: MacModel
    @State private var showingReset = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "pencil.tip.crop.circle.fill").font(.system(size: 38)).foregroundStyle(WhittleTheme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Whittle").font(.title2.bold())
                    Text("Fast screen annotation for agentic dev.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(24)
            Divider()
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 12) {
                        ConnectionBadge(connected: model.connected, text: model.peerName)
                        if let image = qrCode {
                            Image(nsImage: image).interpolation(.none).resizable().scaledToFit().frame(width: 190, height: 190)
                                .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 16))
                                .accessibilityLabel("Pairing QR code")
                        }
                        Text("Open Whittle on your iPad and scan this code.").font(.callout)
                        Button("Copy Pairing Code", systemImage: "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(model.ticket.code, forType: .string)
                        }.accessibilityIdentifier("copyPairingCode")
                        Text("The code grants access to your screenshots. Share it only with your own device.")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    GroupBox("Shortcuts") {
                        VStack(alignment: .leading, spacing: 12) {
                            KeyboardShortcuts.Recorder("Capture region", name: .captureRegion)
                            KeyboardShortcuts.Recorder("Paste screenshot", name: .pasteScreenshot)
                        }.padding(8)
                    }
                    GroupBox("General") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Launch Whittle at login", isOn: $launchAtLogin).onChange(of: launchAtLogin) { _, enabled in
                                do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                                catch { model.error = error.localizedDescription }
                            }
                            Button("Screen Recording Settings…", systemImage: "rectangle.dashed.badge.record") { model.openScreenPermissions() }
                            HStack {
                                Text("Updates arrive through TestFlight.").foregroundStyle(.secondary)
                                Spacer()
                                Link("Open TestFlight", destination: URL(string: "itms-beta://")!)
                            }.font(.caption)
                        }.padding(8)
                    }
                    DisclosureGroup("Connection details") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(model.connectionDetail.isEmpty ? "Local encrypted connection" : model.connectionDetail)
                            Text("Pairing fingerprint: \(model.ticket.fingerprint)").textSelection(.enabled)
                            ForEach(model.ticket.hosts, id: \.self) { Text("\($0):\(model.ticket.port)").textSelection(.enabled) }
                            Text("Allow Whittle in Local Network privacy settings and in the Mac’s Firewall options. If you use a VPN, allow local network access there too.").foregroundStyle(.secondary)
                            Button("Network Settings…") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension")!)
                            }
                            Button("Restart Connection") { model.startListening() }
                            Button("Reset Pairing…", role: .destructive) { showingReset = true }
                        }.font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    }
                    if let error = model.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                }.padding(24)
            }
        }
        .frame(width: 480, height: 660)
        .confirmationDialog("Reset pairing? Your iPad will need to scan the new code. Saved screenshots are kept.", isPresented: $showingReset) {
            Button("Reset Pairing", role: .destructive) { model.resetPairing() }
        }
    }

    private var qrCode: NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(model.ticket.code.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 5, y: 5)),
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
    }
}

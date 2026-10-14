import SwiftUI
import WhittleCore

struct PadPairingView: View {
    @Bindable var model: PadModel
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var address = ""
    @State private var confirmingForget = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: model.connected ? "link.circle.fill" : "macbook.and.ipad")
                        .font(.system(size: 64, weight: .light)).foregroundStyle(WhittleTheme.accent).padding(.top, 24)
                    VStack(spacing: 8) {
                        Text(model.ticket == nil ? "Your Mac, meet your iPad." : model.ticket?.name ?? "Your Mac").font(.title2.bold())
                        Text(model.ticket == nil ? "Open Whittle in your Mac’s menu bar, then scan its pairing code." : "\(model.connectionText)")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    if model.ticket != nil {
                        Button("Reconnect", systemImage: "arrow.clockwise") { model.reconnect() }.buttonStyle(.borderedProminent)
                        if !model.connected {
                            Text("On your Mac, allow Whittle in Local Network privacy settings and Firewall options. A VPN may also need to allow local network access.")
                                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        DisclosureGroup("Connect using an address") {
                            VStack(alignment: .leading, spacing: 12) {
                                if let ticket = model.ticket { Text("Pairing fingerprint: \(ticket.fingerprint)").font(.caption.monospaced()) }
                                Text("Enter an address from Connection Details in Whittle on your Mac.").font(.caption).foregroundStyle(.secondary)
                                TextField("Mac IP address or hostname", text: $address).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                                Button("Use Address") { model.useAddress(address) }.disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
                            }.padding(.top, 12)
                        }
                        Divider()
                    }
                    Button { model.scanning = true } label: {
                        Label(model.ticket == nil ? "Scan Pairing Code" : "Scan Another Code", systemImage: "qrcode.viewfinder").frame(maxWidth: .infinity).padding(8)
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Or paste the pairing code").font(.subheadline.weight(.medium))
                        TextField("whittle://pair/…", text: $code, axis: .vertical)
                            .font(.system(.caption, design: .monospaced)).lineLimit(3...5)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("pairingCode")
                        HStack {
                            PasteButton(payloadType: String.self) { values in code = values.first ?? "" }.labelStyle(.titleAndIcon)
                            Spacer()
                            Button("Pair Mac") { model.pair(code: code) }.disabled(code.isEmpty).accessibilityIdentifier("pairMac")
                        }
                    }
                    if let error = model.error { Text(error).font(.caption).foregroundStyle(.red) }
                    if model.ticket != nil { Button("Forget This Mac…", role: .destructive) { confirmingForget = true }.font(.callout) }
                    Text("Screenshots and notes travel directly between your devices over an encrypted connection.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding(32).frame(maxWidth: 500)
            }
            .navigationTitle("Pairing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .navigationDestination(isPresented: $model.scanning) {
                QRScanner { code in model.scanning = false; model.pair(code: code) }
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle("Scan Your Mac’s Code")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Cancel") { model.scanning = false } } }
            }
        }
        .confirmationDialog("Forget this Mac? Your saved annotations stay on the iPad.", isPresented: $confirmingForget) {
            Button("Forget Mac", role: .destructive) { model.forgetMac() }
        }
        .onChange(of: model.showingPairing) { _, shown in if !shown { dismiss() } }
    }
}

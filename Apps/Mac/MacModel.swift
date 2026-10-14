import AppKit
import Network
import Observation
import SystemConfiguration
import WhittleCore

@MainActor @Observable
final class MacModel {
    let library: ScreenshotLibrary
    private(set) var ticket: PairingTicket
    private(set) var connected = false
    private(set) var peerName = "Waiting for your iPad"
    private(set) var connectionDetail = ""
    private(set) var latestExport: ExportedFiles?
    private(set) var latestTitle = ""
    var error: String?
    var isCapturing = false
    var needsScreenPermission = false
    let root: URL
    private var listener: NWListener?
    private var peer: PeerConnection?
    private var peerID: UUID?
    private var candidates: [UUID: PeerConnection] = [:]
    private var heartbeat: Task<Void, Never>?
    private var lastHeard = Date()
    private var completedExports: [UUID] = []
    private var remoteIDs = Set<UUID>()
    private let permissionGuide = ScreenPermissionGuide()

    init() throws {
        root = try AppDirectories.root()
        library = try ScreenshotLibrary(directory: root.appendingPathComponent("Screenshots"))
        let name = Host.current().localizedName ?? "Mac"
        if AppDirectories.isTesting {
            ticket = try PairingTicket(name: "Test Mac", hosts: ["127.0.0.1"])
            if AppDirectories.isUITesting { try library.receive(DemoScreenshot.record()) }
        } else {
            var identity = try PairingVault.load() ?? PairingTicket(name: name, hosts: Self.localHosts())
            identity.name = name
            identity.hosts = Self.localHosts()
            ticket = identity
            try PairingVault.save(ticket)
            if let data = try? Data(contentsOf: root.appendingPathComponent("export-receipts.json")) {
                completedExports = (try? JSONDecoder().decode([UUID].self, from: data)) ?? []
            }
            startListening()
        }
    }

    func startListening() {
        listener?.cancel()
        do {
            let listener = try NWListener(using: PeerSecurity.parameters(for: ticket), on: .init(rawValue: ticket.port)!)
            self.listener = listener
            listener.service = .init(name: ticket.serviceName, type: "_whittle._tcp")
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready: self.connectionDetail = "Ready on port \(self.ticket.port)"
                    case .failed(let failure): self.connectionDetail = failure.localizedDescription; self.error = "Couldn’t start the connection: \(failure.localizedDescription)"
                    case .waiting(let failure): self.connectionDetail = failure.localizedDescription
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.start(queue: DispatchQueue(label: "app.whittle.listener"))
        } catch { self.error = error.localizedDescription }
    }

    func resetPairing() {
        do {
            let replacement = try PairingTicket(name: ticket.name, hosts: Self.localHosts(), port: ticket.port)
            try PairingVault.save(replacement)
            ticket = replacement
            peer?.cancel()
            candidates.values.forEach { $0.cancel() }
            candidates.removeAll()
            connected = false
            peerName = "Waiting for your iPad"
            startListening()
        } catch { self.error = error.localizedDescription }
    }

    func addScreenshot(_ data: Data, title: String) throws {
        guard let image = NSImage(data: data), let bitmap = NSBitmapImageRep(data: data),
              let png = bitmap.representation(using: .png, properties: [:]), image.isValid else { throw WhittleError.invalidDocument }
        let document = AnnotationDocument(title: title, pixelWidth: bitmap.pixelsWide, pixelHeight: bitmap.pixelsHigh)
        let record = ScreenshotRecord(document: document, originalPNG: png)
        try library.receive(record)
        library.selectedID = document.id
        send(.capture(record))
    }

    func importClipboard() {
        if let image = NSImage(pasteboard: .general), let tiff = image.tiffRepresentation {
            do { try addScreenshot(tiff, title: "Pasted screenshot") } catch { self.error = error.localizedDescription }
        } else { error = "Copy an image, then choose Paste Screenshot." }
    }

    func importFiles(_ urls: [URL]) {
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do { try addScreenshot(Data(contentsOf: url), title: url.deletingPathExtension().lastPathComponent) }
            catch { self.error = error.localizedDescription }
        }
    }

    func copyLatest() {
        guard let latestExport else { return }
        do { try FileClipboard.write(latestExport) } catch { self.error = error.localizedDescription }
    }

    func openScreenPermissions() { permissionGuide.open() }

    private func accept(_ connection: NWConnection) {
        guard candidates.count < 4 else { connection.cancel(); return }
        let id = UUID()
        let candidate = PeerConnection(connection: connection)
        candidates[id] = candidate
        candidate.onMessage = { [weak self] message in Task { @MainActor in self?.receive(message, from: id) } }
        candidate.onState = { [weak self, weak candidate] state in
            Task { @MainActor in
                guard let self, let candidate else { return }
                switch state {
                case .ready:
                    if self.peerID != id { self.peer?.cancel() }
                    self.remoteIDs.removeAll()
                    self.peer = candidate
                    self.peerID = id
                    self.connected = true
                    self.lastHeard = Date()
                    candidate.send(.hello(version: 1, name: self.ticket.name))
                    candidate.send(.inventory(self.library.documents.map(\.version)))
                    self.startHeartbeat()
                case .failed, .cancelled:
                    self.candidates[id] = nil
                    if self.peerID == id {
                        self.peer = nil; self.peerID = nil; self.connected = false
                        self.peerName = "Waiting for your iPad"
                    }
                default: break
                }
            }
        }
        candidate.start()
        Task { [weak self, weak candidate] in
            try? await Task.sleep(for: .seconds(10))
            if self?.peerID != id { candidate?.cancel() }
        }
    }

    private func receive(_ message: WireMessage, from id: UUID) {
        guard id == peerID else { return }
        lastHeard = Date()
        do {
            switch message {
            case .hello(let version, let name):
                guard version == 1 else { throw WhittleError.unsupportedProtocol }
                peerName = String(name.prefix(200))
            case .inventory(let remote):
                remoteIDs = Set(remote.map(\.id))
                let missing = WireCodec.missingDocuments(local: library.documents.map(\.version), remote: remote)
                if !missing.isEmpty { send(.request(missing)) }
            case .request(let ids):
                for id in ids.prefix(500) { try sendRecord(id) }
            case .capture(let record): try library.receive(record); send(.acknowledge(record.document.version))
            case .annotations(let document): try library.receive(document); send(.acknowledge(document.version))
            case .export(let feedback): try export(feedback)
            case .ping: send(.pong)
            case .error(let detail): error = String(detail.prefix(1000))
            default: break
            }
        } catch {
            self.error = error.localizedDescription
            send(.error(error.localizedDescription))
        }
    }

    private func export(_ feedback: FeedbackExport) throws {
        if completedExports.contains(feedback.requestID) { send(.exported(requestID: feedback.requestID)); return }
        try library.receive(feedback.document)
        let files = try ExportedFiles(document: feedback.document, annotatedPNG: feedback.annotatedPNG, directory: root.appendingPathComponent("Exports"))
        try FileClipboard.write(files)
        latestExport = files
        latestTitle = feedback.document.title
        completedExports = Array((completedExports + [feedback.requestID]).suffix(100))
        try JSONEncoder().encode(completedExports).write(to: root.appendingPathComponent("export-receipts.json"), options: .atomic)
        send(.exported(requestID: feedback.requestID))
    }

    private func sendRecord(_ id: UUID) throws {
        if remoteIDs.contains(id), let document = try library.repository.document(id) { send(.annotations(document)) }
        else if let record = try library.repository.record(id) { send(.capture(record)) }
    }

    private func send(_ message: WireMessage) {
        peer?.send(message) { [weak self] failure in
            if let failure { Task { @MainActor in self?.error = failure.localizedDescription } }
        }
    }

    private func startHeartbeat() {
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled, let self else { return }
                if Date().timeIntervalSince(self.lastHeard) > 35 { self.peer?.cancel(); return }
                self.send(.ping)
            }
        }
    }

    static func localHosts() -> [String] {
        var hosts: [String] = []
        if let name = SCDynamicStoreCopyLocalHostName(nil) as String? { hosts.append(name + ".local") }
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&interfaces) == 0 {
            defer { freeifaddrs(interfaces) }
            var cursor = interfaces
            while let interface = cursor {
                defer { cursor = interface.pointee.ifa_next }
                let flags = interface.pointee.ifa_flags
                guard let address = interface.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                      flags & UInt32(IFF_UP) != 0,
                      flags & UInt32(IFF_LOOPBACK | IFF_POINTOPOINT) == 0 else { continue }
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(address, socklen_t(address.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                    hosts.append(String(cString: buffer))
                }
            }
        }
        return hosts.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }
}

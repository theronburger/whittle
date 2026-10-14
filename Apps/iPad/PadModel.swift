import Foundation
import Network
import Observation
import UIKit
import WhittleCore

@MainActor @Observable
final class PadModel {
    let library: ScreenshotLibrary
    private(set) var ticket: PairingTicket?
    private(set) var connected = false
    private(set) var connectionText = "Pair your Mac"
    private(set) var copyStatus: String?
    var error: String?
    var showingPairing = false
    var scanning = false
    private var peer: PeerConnection?
    private var browser: NWBrowser?
    private var retry: Task<Void, Never>?
    private var sync: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var connectionTimeout: Task<Void, Never>?
    private var active = true
    private var generation = UUID()
    private var candidateIndex = 0
    private var attempts = 0
    private var discoveredEndpoint: NWEndpoint?
    private var lastHeard = Date()
    private var pendingExports: [FeedbackExport] = []
    private var remoteIDs = Set<UUID>()
    private let outbox: URL

    init() throws {
        let root = try AppDirectories.root()
        library = try ScreenshotLibrary(directory: root.appendingPathComponent("Screenshots"))
        outbox = root.appendingPathComponent("outbox.json")
        if let data = try? Data(contentsOf: outbox) { pendingExports = try JSONDecoder().decode([FeedbackExport].self, from: data) }
        if AppDirectories.isTesting {
            if AppDirectories.isUITesting { try library.receive(DemoScreenshot.record()) }
        } else {
            ticket = try PairingVault.load()
            #if DEBUG
            print("Whittle pairing fingerprint: \(ticket?.fingerprint ?? "unpaired")")
            fflush(stdout)
            #endif
            if ticket != nil { beginDiscovery(); connect() } else { showingPairing = true }
        }
        library.onEdit = { [weak self] _ in self?.scheduleSync() }
    }

    func pair(code: String) {
        scanning = false
        do {
            let ticket = try PairingTicket(code: code)
            #if DEBUG
            print("Whittle pairing code accepted: \(ticket.fingerprint)")
            fflush(stdout)
            #endif
            try PairingVault.save(ticket)
            self.ticket = ticket
            attempts = 0; candidateIndex = 0; discoveredEndpoint = nil
            showingPairing = false
            error = nil
            beginDiscovery()
            connect()
        } catch { self.error = error.localizedDescription }
    }

    func forgetMac() {
        do {
            try PairingVault.remove()
            active = false
            stopConnection()
            browser?.cancel(); browser = nil
            ticket = nil
            connectionText = "Pair your Mac"
            active = true
        } catch { self.error = error.localizedDescription }
    }

    func setActive(_ active: Bool) {
        self.active = active
        if active {
            if ticket != nil && !connected { beginDiscovery(); connect() }
        } else {
            sync?.cancel()
            sendInventory()
            stopConnection()
            browser?.cancel(); browser = nil
        }
    }

    func reconnect() {
        attempts = 0
        candidateIndex = 0
        beginDiscovery()
        connect()
    }

    func useAddress(_ address: String) {
        guard var ticket else { return }
        let host = address.trimmingCharacters(in: .whitespacesAndNewlines)
        ticket.hosts = [host] + ticket.hosts.filter { $0 != host }
        do { try ticket.validate(); try PairingVault.save(ticket); self.ticket = ticket; discoveredEndpoint = nil; reconnect() }
        catch { self.error = error.localizedDescription }
    }

    func copyFeedback(document: AnnotationDocument, png: Data) {
        do {
            let feedback = FeedbackExport(document: document, annotatedPNG: png)
            pendingExports.removeAll { $0.document.id == document.id }
            pendingExports.append(feedback)
            try saveOutbox()
            copyStatus = connected ? "Sending to Mac…" : "Queued — copies when your Mac reconnects"
            if connected { send(.export(feedback)) }
        } catch { self.error = error.localizedDescription }
    }

    private func beginDiscovery() {
        browser?.cancel()
        guard !AppDirectories.isTesting, let ticket, active else { return }
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_whittle._tcp", domain: nil), using: parameters)
        self.browser = browser
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let endpoint = results.first { result in
                if case .service(let name, _, _, _) = result.endpoint { return name == ticket.serviceName }
                return false
            }?.endpoint
            Task { @MainActor in
                guard let self, self.ticket?.hostID == ticket.hostID else { return }
                self.discoveredEndpoint = endpoint
                if endpoint != nil && self.peer == nil { self.connect() }
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .waiting(let error) = state {
                Task { @MainActor in if self?.connected == false { self?.connectionText = "Discovery unavailable: \(error.localizedDescription)" } }
            }
        }
        browser.start(queue: DispatchQueue(label: "app.whittle.discovery"))
    }

    private func connect() {
        guard !AppDirectories.isTesting, active, let ticket else { return }
        stopConnection()
        remoteIDs.removeAll()
        connectionText = "Connecting to \(ticket.name)…"
        let endpoints = (discoveredEndpoint.map { [$0] } ?? []) + ticket.hosts.map {
            NWEndpoint.hostPort(host: .init($0), port: .init(rawValue: ticket.port)!)
        }
        guard !endpoints.isEmpty else { return }
        let endpoint = endpoints[candidateIndex % endpoints.count]
        candidateIndex += 1
        let token = UUID()
        generation = token
        let peer = PeerConnection(endpoint: endpoint, ticket: ticket)
        self.peer = peer
        peer.onMessage = { [weak self] message in
            Task { @MainActor in guard self?.generation == token else { return }; self?.receive(message) }
        }
        peer.onState = { [weak self] state in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                switch state {
                case .ready:
                    self.connectionTimeout?.cancel()
                    self.retry?.cancel(); self.retry = nil
                    self.connected = true; self.attempts = 0; self.lastHeard = Date()
                    self.connectionText = ticket.name
                    self.send(.hello(version: 1, name: UIDevice.current.name))
                    self.sendInventory()
                    for feedback in self.pendingExports { self.send(.export(feedback)) }
                    self.startHeartbeat()
                case .failed(let error), .waiting(let error):
                    self.connectionText = "Reconnecting · \(error.localizedDescription)"
                    self.scheduleReconnect()
                case .cancelled: self.connected = false; self.scheduleReconnect()
                default: break
                }
            }
        }
        peer.start()
        connectionTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self, self.generation == token, !self.connected else { return }
            self.scheduleReconnect()
        }
    }

    private func stopConnection() {
        generation = UUID()
        retry?.cancel(); connectionTimeout?.cancel(); heartbeat?.cancel()
        peer?.cancel(); peer = nil
        connected = false
    }

    private func scheduleReconnect() {
        guard active, retry == nil || retry?.isCancelled == true else { return }
        connected = false
        attempts += 1
        let seconds = min(10, max(1, attempts))
        retry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            self.retry = nil
            self.connect()
        }
    }

    private func receive(_ message: WireMessage) {
        lastHeard = Date()
        do {
            switch message {
            case .hello(let version, _): guard version == 1 else { throw WhittleError.unsupportedProtocol }
            case .inventory(let remote):
                remoteIDs = Set(remote.map(\.id))
                let missing = WireCodec.missingDocuments(local: library.documents.map(\.version), remote: remote)
                if !missing.isEmpty { send(.request(missing)) }
            case .request(let ids):
                for id in ids.prefix(500) {
                    if remoteIDs.contains(id), let document = try library.repository.document(id) { send(.annotations(document)) }
                    else if let record = try library.repository.record(id) { send(.capture(record)) }
                }
            case .capture(let record): try library.receive(record); send(.acknowledge(record.document.version))
            case .annotations(let document): try library.receive(document); send(.acknowledge(document.version))
            case .exported(let requestID):
                guard pendingExports.contains(where: { $0.requestID == requestID }) else { return }
                pendingExports.removeAll { $0.requestID == requestID }
                try saveOutbox()
                copyStatus = pendingExports.isEmpty ? "Copied on your Mac · image + notes" : "Sending to Mac…"
            case .error(let detail): error = String(detail.prefix(1000)); copyStatus = nil
            case .ping: send(.pong)
            default: break
            }
        } catch { self.error = error.localizedDescription }
    }

    private func sendInventory() { send(.inventory(library.documents.map(\.version))) }

    private func scheduleSync() {
        sync?.cancel()
        sync = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            self.sendInventory()
        }
    }

    private func send(_ message: WireMessage) {
        guard connected else { return }
        peer?.send(message) { [weak self] failure in
            if let failure { Task { @MainActor in self?.error = failure.localizedDescription } }
        }
    }

    private func saveOutbox() throws { try JSONEncoder().encode(pendingExports).write(to: outbox, options: .atomic) }

    private func startHeartbeat() {
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled, let self else { return }
                if Date().timeIntervalSince(self.lastHeard) > 30 { self.scheduleReconnect(); return }
                self.send(.ping)
            }
        }
    }
}

import Foundation
import Network
import Security

public enum PeerSecurity {
    public static func parameters(for ticket: PairingTicket) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_append_tls_ciphersuite(options, tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!)
        let key = ticket.secret.withUnsafeBytes { DispatchData(bytes: $0) }
        let identity = Data(ticket.hostID.uuidString.utf8).withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(options, key as __DispatchData, identity as __DispatchData)
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        parameters.includePeerToPeer = true
        parameters.allowLocalEndpointReuse = true
        return parameters
    }
}

public final class PeerConnection: @unchecked Sendable {
    public var onMessage: (@Sendable (WireMessage) -> Void)?
    public var onState: (@Sendable (NWConnection.State) -> Void)?
    private let connection: NWConnection
    private let queue: DispatchQueue
    private var stopped = false

    public init(connection: NWConnection, queue: DispatchQueue = DispatchQueue(label: "app.whittle.peer")) {
        self.connection = connection
        self.queue = queue
    }

    public convenience init(endpoint: NWEndpoint, ticket: PairingTicket) {
        self.init(connection: NWConnection(to: endpoint, using: PeerSecurity.parameters(for: ticket)))
    }

    public func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            #if DEBUG
            print("Whittle connection: \(state)")
            #endif
            self.onState?(state)
            if case .ready = state { self.receiveHeader() }
        }
        connection.start(queue: queue)
    }

    public func send(_ message: WireMessage, completion: (@Sendable (Error?) -> Void)? = nil) {
        do {
            let data = try WireCodec.encode(message)
            connection.send(content: data, completion: .contentProcessed { error in completion?(error) })
        } catch { completion?(error) }
    }

    public func cancel() {
        queue.async { [weak self] in
            self?.stopped = true
            self?.connection.cancel()
        }
    }

    private func receiveHeader() {
        guard !stopped else { return }
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, complete, error in
            guard let self else { return }
            guard let data, data.count == 4, error == nil else { self.finish(error); return }
            do { self.receiveBody(size: try WireCodec.frameSize(data)) }
            catch { self.finish(error) }
            if complete { self.finish(nil) }
        }
    }

    private func receiveBody(size: Int) {
        connection.receive(minimumIncompleteLength: size, maximumLength: size) { [weak self] data, _, complete, error in
            guard let self else { return }
            guard let data, data.count == size, error == nil else { self.finish(error); return }
            do {
                let message = try WireCodec.decode(data)
                self.onMessage?(message)
                if complete { self.finish(nil) } else { self.receiveHeader() }
            } catch { self.finish(error) }
        }
    }

    private func finish(_ error: Error?) {
        guard !stopped else { return }
        stopped = true
        connection.cancel()
    }
}

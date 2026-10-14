import Foundation
import Network
import XCTest
@testable import WhittleCore

final class ConnectionTests: XCTestCase {
    func testEncryptedConnectionTransfersOrderedMessagesAndLargeScreenshot() async throws {
        let ticket = try PairingTicket(name: "Test", hosts: ["127.0.0.1"])
        let listener = try NWListener(using: PeerSecurity.parameters(for: ticket), on: .any)
        let listening = expectation(description: "Listening")
        let received = expectation(description: "Screenshot received")
        let replied = expectation(description: "Acknowledgement received")
        let retained = RetainedPeer()
        listener.stateUpdateHandler = { state in if case .ready = state { listening.fulfill() } }
        var document = AnnotationDocument(title: "Large screenshot", pixelWidth: 2000, pixelHeight: 1200)
        document.notes = [.init(anchor: .init(x: 0.2, y: 0.3), text: "Keep this exact: ← 你好")]
        let record = ScreenshotRecord(document: document, originalPNG: Data(repeating: 123, count: 2_000_000))
        listener.newConnectionHandler = { connection in
            let peer = PeerConnection(connection: connection)
            retained.peer = peer
            peer.onMessage = { message in
                if case .capture(let receivedRecord) = message {
                    XCTAssertEqual(receivedRecord, record)
                    peer.send(.acknowledge(receivedRecord.document.version))
                    received.fulfill()
                }
            }
            peer.start()
        }
        listener.start(queue: DispatchQueue(label: "whittle.test.listener"))
        defer { listener.cancel(); retained.peer?.cancel() }
        await fulfillment(of: [listening], timeout: 5)
        let client = PeerConnection(endpoint: .hostPort(host: "127.0.0.1", port: try XCTUnwrap(listener.port)), ticket: ticket)
        client.onState = { state in if case .ready = state { client.send(.hello(version: 1, name: "iPad")); client.send(.capture(record)) } }
        client.onMessage = { message in XCTAssertEqual(message, .acknowledge(record.document.version)); replied.fulfill() }
        client.start()
        defer { client.cancel() }
        await fulfillment(of: [received, replied], timeout: 10, enforceOrder: true)
    }

    func testDifferentPairingSecretCannotAuthenticate() async throws {
        let ticket = try PairingTicket(name: "Test", hosts: ["127.0.0.1"])
        let wrongTicket = try PairingTicket(hostID: ticket.hostID, name: ticket.name, hosts: ticket.hosts)
        let listener = try NWListener(using: PeerSecurity.parameters(for: ticket), on: .any)
        let listening = expectation(description: "Listening")
        let rejected = expectation(description: "Authentication rejected")
        let retained = RetainedPeer()
        listener.stateUpdateHandler = { state in if case .ready = state { listening.fulfill() } }
        listener.newConnectionHandler = { connection in
            let peer = PeerConnection(connection: connection)
            retained.peer = peer
            peer.onMessage = { _ in XCTFail("Unauthenticated peer sent application data") }
            peer.start()
        }
        listener.start(queue: DispatchQueue(label: "whittle.test.rejection"))
        defer { listener.cancel(); retained.peer?.cancel() }
        await fulfillment(of: [listening], timeout: 5)
        let client = PeerConnection(endpoint: .hostPort(host: "127.0.0.1", port: try XCTUnwrap(listener.port)), ticket: wrongTicket)
        client.onState = { state in
            switch state {
            case .ready: XCTFail("Wrong pairing secret authenticated")
            case .waiting, .failed: rejected.fulfill()
            default: break
            }
        }
        client.start()
        defer { client.cancel() }
        await fulfillment(of: [rejected], timeout: 5)
    }
}

private final class RetainedPeer: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: PeerConnection?
    var peer: PeerConnection? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

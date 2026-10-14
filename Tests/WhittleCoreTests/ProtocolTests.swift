import Foundation
import Testing
@testable import WhittleCore

struct ProtocolTests {
    @Test func pairingCodeRoundTripsAndPreservesIdentityAcrossAddressChanges() throws {
        var ticket = try PairingTicket(name: "Work Mac", hosts: ["work.local", "192.168.0.12"])
        #expect(try PairingTicket(code: ticket.code) == ticket)
        let originalIdentity = ticket.hostID
        let originalSecret = ticket.secret
        ticket.hosts = ["10.0.0.4"]
        #expect(try PairingTicket(code: ticket.code).hostID == originalIdentity)
        #expect(ticket.secret == originalSecret)
    }

    @Test(arguments: ["", "https://example.com", "whittle://pair/not-a-ticket", "whittle://pair/../../etc/passwd"])
    func rejectsBadPairingCodes(code: String) {
        #expect(throws: WhittleError.self) { try PairingTicket(code: code) }
    }

    @Test func requiresStrongPairingSecret() {
        #expect(throws: WhittleError.self) { try PairingTicket(name: "Mac", hosts: ["mac.local"], secret: Data([1])) }
    }

    @Test func framingPreservesUnicodeAndInk() throws {
        var document = AnnotationDocument(title: "Übersicht", pixelWidth: 1000, pixelHeight: 800)
        document.notes = [.init(anchor: .init(x: 0.4, y: 0.7), text: "← Move this · 你好")]
        document.ink = Data(0...255)
        let message = WireMessage.annotations(document)
        let frame = try WireCodec.encode(message)
        #expect(try WireCodec.frameSize(frame.prefix(4)) == frame.count - 4)
        #expect(try WireCodec.decode(frame.dropFirst(4)) == message)
    }

    @Test func rejectsUnboundedFrames() {
        #expect(throws: WhittleError.self) { try WireCodec.frameSize(Data([255, 255, 255, 255])) }
        #expect(throws: WhittleError.self) { try WireCodec.frameSize(Data([0, 0, 0, 0])) }
        #expect(throws: WhittleError.self) { try WireCodec.frameSize(Data([1])) }
    }

    @Test func reconnectRequestsOnlyMissingOrNewerDocuments() {
        let first = UUID(), second = UUID(), third = UUID()
        let local = [DocumentVersion(id: first, revision: 7), .init(id: second, revision: 2)]
        let remote = [DocumentVersion(id: first, revision: 6), .init(id: second, revision: 3), .init(id: third, revision: 0)]
        #expect(WireCodec.missingDocuments(local: local, remote: remote) == [second, third])
    }
}

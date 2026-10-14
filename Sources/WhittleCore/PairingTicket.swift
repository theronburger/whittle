import CryptoKit
import Foundation
import Security

public struct PairingTicket: Codable, Equatable, Sendable {
    public let hostID: UUID
    public var name: String
    public var hosts: [String]
    public var port: UInt16
    public let secret: Data

    public init(hostID: UUID = UUID(), name: String, hosts: [String], port: UInt16 = 49_857, secret: Data? = nil) throws {
        self.hostID = hostID
        self.name = name
        self.hosts = hosts
        self.port = port
        if let secret { self.secret = secret }
        else {
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw WhittleError.invalidPairingCode }
            self.secret = Data(bytes)
        }
        try validate()
    }

    public var serviceName: String { "Whittle-" + hostID.uuidString }
    public var fingerprint: String { SHA256.hash(data: secret).prefix(6).map { String(format: "%02x", $0) }.joined(separator: ":") }

    public func validate() throws {
        guard secret.count == 32, port > 0, !hosts.isEmpty, hosts.count <= 20,
              name.count <= 200, hosts.allSatisfy({ !$0.isEmpty && $0.count <= 255 && !$0.contains("/") && !$0.contains(" ") }) else {
            throw WhittleError.invalidPairingCode
        }
    }

    public var code: String {
        let data = (try? JSONEncoder().encode(self)) ?? Data()
        return "whittle://pair/" + data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    public init(code: String) throws {
        let prefix = "whittle://pair/"
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix), trimmed.count < 10_000 else { throw WhittleError.invalidPairingCode }
        var encoded = String(trimmed.dropFirst(prefix.count)).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded), let ticket = try? JSONDecoder().decode(Self.self, from: data) else {
            throw WhittleError.invalidPairingCode
        }
        try ticket.validate()
        self = ticket
    }
}

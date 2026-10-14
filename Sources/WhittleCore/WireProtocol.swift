import Foundation

public struct FeedbackExport: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let document: AnnotationDocument
    public let annotatedPNG: Data

    public init(requestID: UUID = UUID(), document: AnnotationDocument, annotatedPNG: Data) {
        self.requestID = requestID
        self.document = document
        self.annotatedPNG = annotatedPNG
    }
}

public enum WireMessage: Codable, Equatable, Sendable {
    case hello(version: Int, name: String)
    case inventory([DocumentVersion])
    case request([UUID])
    case capture(ScreenshotRecord)
    case annotations(AnnotationDocument)
    case acknowledge(DocumentVersion)
    case export(FeedbackExport)
    case exported(requestID: UUID)
    case error(String)
    case ping
    case pong
}

public enum WireCodec {
    public static let maximumFrameSize = 32_000_000

    public static func encode(_ message: WireMessage) throws -> Data {
        let data = try JSONEncoder().encode(message)
        guard data.count <= maximumFrameSize else { throw WhittleError.messageTooLarge }
        let size = UInt32(data.count)
        var frame = Data([UInt8(size >> 24), UInt8((size >> 16) & 255), UInt8((size >> 8) & 255), UInt8(size & 255)])
        frame.append(data)
        return frame
    }

    public static func decode(_ data: Data) throws -> WireMessage {
        guard data.count <= maximumFrameSize else { throw WhittleError.messageTooLarge }
        return try JSONDecoder().decode(WireMessage.self, from: data)
    }

    public static func frameSize(_ header: Data) throws -> Int {
        guard header.count == 4 else { throw WhittleError.invalidDocument }
        let size = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard size > 0, size <= maximumFrameSize else { throw WhittleError.messageTooLarge }
        return Int(size)
    }

    public static func missingDocuments(local: [DocumentVersion], remote: [DocumentVersion]) -> [UUID] {
        let versions = Dictionary(local.map { ($0.id, $0.revision) }, uniquingKeysWith: max)
        return remote.filter { (versions[$0.id] ?? -1) < $0.revision }.map(\.id)
    }
}

import Foundation

public struct CanvasPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = min(1, max(0, x))
        self.y = min(1, max(0, y))
    }

    public var isValid: Bool { x.isFinite && y.isFinite && (0...1).contains(x) && (0...1).contains(y) }
}

public enum AnnotationColor: String, Codable, CaseIterable, Sendable {
    case coral, amber, mint, blue, violet, white
}

public struct AnnotationNote: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var anchor: CanvasPoint
    public var position: CanvasPoint
    public var text: String
    public var color: AnnotationColor

    public init(id: UUID = UUID(), anchor: CanvasPoint, position: CanvasPoint? = nil, text: String = "", color: AnnotationColor = .amber) {
        self.id = id
        self.anchor = anchor
        self.position = position ?? anchor
        self.text = text
        self.color = color
    }
}

public struct AnnotationArrow: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var start: CanvasPoint
    public var end: CanvasPoint
    public var color: AnnotationColor

    public init(id: UUID = UUID(), start: CanvasPoint, end: CanvasPoint, color: AnnotationColor = .coral) {
        self.id = id
        self.start = start
        self.end = end
        self.color = color
    }
}

public struct AnnotationDocument: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var capturedAt: Date
    public var modifiedAt: Date
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var revision: Int
    public var ink: Data
    public var notes: [AnnotationNote]
    public var arrows: [AnnotationArrow]

    public init(id: UUID = UUID(), title: String, pixelWidth: Int, pixelHeight: Int, capturedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.capturedAt = capturedAt
        self.modifiedAt = capturedAt
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.revision = 0
        self.ink = Data()
        self.notes = []
        self.arrows = []
    }

    public var version: DocumentVersion { .init(id: id, revision: revision) }

    public mutating func markChanged() {
        revision += 1
        modifiedAt = Date()
    }

    public func validate() throws {
        guard revision >= 0, pixelWidth > 0, pixelHeight > 0, pixelWidth <= 32_768, pixelHeight <= 32_768,
              title.count <= 1_024, ink.count <= 12_000_000, notes.count <= 1_000, arrows.count <= 2_000,
              Set(notes.map(\.id)).count == notes.count, Set(arrows.map(\.id)).count == arrows.count,
              notes.allSatisfy({ $0.anchor.isValid && $0.position.isValid && $0.text.count <= 100_000 }),
              arrows.allSatisfy({ $0.start.isValid && $0.end.isValid }) else {
            throw WhittleError.invalidDocument
        }
    }

    public var markdown: String {
        var lines = ["# \(title)", "", "Screenshot: \(pixelWidth) × \(pixelHeight) pixels", ""]
        for (index, note) in notes.enumerated() {
            let x = Int((note.anchor.x * Double(pixelWidth)).rounded())
            let y = Int((note.anchor.y * Double(pixelHeight)).rounded())
            lines += ["## Note \(index + 1) — at (\(x), \(y))", "", note.text.isEmpty ? "(No text)" : note.text, ""]
        }
        if notes.isEmpty { lines += ["See the accompanying annotated image for visual feedback.", ""] }
        return lines.joined(separator: "\n")
    }
}

public struct DocumentVersion: Codable, Equatable, Sendable {
    public let id: UUID
    public let revision: Int
    public init(id: UUID, revision: Int) { self.id = id; self.revision = revision }
}

public struct ScreenshotRecord: Codable, Equatable, Sendable {
    public var document: AnnotationDocument
    public var originalPNG: Data
    public init(document: AnnotationDocument, originalPNG: Data) { self.document = document; self.originalPNG = originalPNG }
}

public enum WhittleError: Error, LocalizedError {
    case invalidDocument, invalidPairingCode, messageTooLarge, unsupportedProtocol, missingScreenshot, storage(String)

    public var errorDescription: String? {
        switch self {
        case .invalidDocument: return "This annotation document is invalid."
        case .invalidPairingCode: return "That pairing code isn’t valid. Copy a new one from Whittle on your Mac."
        case .messageTooLarge: return "This screenshot is too large to transfer (32 MB maximum)."
        case .unsupportedProtocol: return "Update Whittle on both devices to connect."
        case .missingScreenshot: return "The original screenshot hasn’t arrived yet. Reconnect to your Mac."
        case .storage(let detail): return "Couldn’t save your changes: \(detail)"
        }
    }
}

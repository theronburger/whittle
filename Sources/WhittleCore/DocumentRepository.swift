import Foundation

public final class DocumentRepository {
    public let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let files = FileManager.default

    public init(directory: URL) throws {
        self.directory = directory
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        encoder.outputFormatting = [.sortedKeys]
    }

    public func documents() throws -> [AnnotationDocument] {
        try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "whittle" }
            .compactMap { url in
                guard UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil else { return nil }
                let metadata = url.appendingPathComponent("document.json")
                guard files.fileExists(atPath: metadata.path) else { return nil }
                let document = try decoder.decode(AnnotationDocument.self, from: Data(contentsOf: metadata))
                try document.validate()
                return document
            }
            .sorted { $0.capturedAt > $1.capturedAt }
    }

    public func document(_ id: UUID) throws -> AnnotationDocument? {
        let url = folder(id).appendingPathComponent("document.json")
        guard files.fileExists(atPath: url.path) else { return nil }
        let document = try decoder.decode(AnnotationDocument.self, from: Data(contentsOf: url))
        try document.validate()
        return document
    }

    public func original(_ id: UUID) throws -> Data {
        try Data(contentsOf: folder(id).appendingPathComponent("original.png"))
    }

    public func record(_ id: UUID) throws -> ScreenshotRecord? {
        guard let document = try document(id) else { return nil }
        return ScreenshotRecord(document: document, originalPNG: try original(id))
    }

    @discardableResult
    public func receive(_ record: ScreenshotRecord) throws -> Bool {
        try record.document.validate()
        guard !record.originalPNG.isEmpty, record.originalPNG.count <= 24_000_000 else { throw WhittleError.messageTooLarge }
        try files.createDirectory(at: folder(record.document.id), withIntermediateDirectories: true)
        let originalURL = folder(record.document.id).appendingPathComponent("original.png")
        if !files.fileExists(atPath: originalURL.path) { try record.originalPNG.write(to: originalURL, options: .atomic) }
        return try save(record.document)
    }

    @discardableResult
    public func save(_ document: AnnotationDocument) throws -> Bool {
        try document.validate()
        if let saved = try self.document(document.id), saved.revision >= document.revision { return false }
        guard files.fileExists(atPath: folder(document.id).appendingPathComponent("original.png").path) else {
            throw WhittleError.missingScreenshot
        }
        try encoder.encode(document).write(to: folder(document.id).appendingPathComponent("document.json"), options: .atomic)
        return true
    }

    public func delete(_ id: UUID) throws {
        let url = folder(id)
        if files.fileExists(atPath: url.path) { try files.removeItem(at: url) }
    }

    private func folder(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".whittle", isDirectory: true) }
}

public struct ExportedFiles {
    public let image: URL
    public let notes: URL
    public var urls: [URL] { [image, notes] }

    public init(document: AnnotationDocument, annotatedPNG: Data, directory: URL) throws {
        try document.validate()
        guard !annotatedPNG.isEmpty, annotatedPNG.count <= 24_000_000 else { throw WhittleError.messageTooLarge }
        let exportDirectory = directory.appendingPathComponent(document.id.uuidString).appendingPathComponent("r\(document.revision)")
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let basename = "Whittle-\(document.id.uuidString.prefix(8))-r\(document.revision)"
        image = exportDirectory.appendingPathComponent(basename + ".png")
        notes = exportDirectory.appendingPathComponent(basename + ".md")
        try annotatedPNG.write(to: image, options: .atomic)
        let markdown = document.markdown + "\nAnnotated image: [\(image.lastPathComponent)](\(image.lastPathComponent))\n"
        try markdown.write(to: notes, atomically: true, encoding: .utf8)
    }
}
